//+------------------------------------------------------------------+
//|                                         Indicator: SpikeDetector |
//|                                       Created By Steven Nkeneng  |
//|                                     https://www.stevennkeneng.com|
//+------------------------------------------------------------------+
#property copyright "Steven Nkeneng (Trading & Code) - 2021-2021"
#property link "https://tradingandcode.com"
#property version "1.00"
#property description "Robot  trading  signal based on ..."
#property description " "
#property description "WARNING : You use this software at your own risk."
#property description "The creator of these plugins cannot be held responsible for damage or loss."
#property description " "
#property description "Find More on tradingandcode.com"
#property icon "\\Images\\logo-steven.ico"
#property tester_indicator "Spikedetector"

#define programname "spiky"

enum TradeType
{
   Buy = 1,
   Sell = 2
};

//+------------------------------------------------------------------+
//|     inputs                                                             |
//+------------------------------------------------------------------+
input int MagicNumber = 164528;
input double MM_Percent = 1;
input double tradeVolume = 20;
input int MaxTradeDurationBars = 3; // maximum trade duration
input int MinTradeDurationBars = 3; // minimum trade duration
input int martingalMultiplier = 2;  // martingale multiplier
input TradeType tradeType = Buy;

// Importer librairie CTrade
#include <Trade\Trade.mqh>
CTrade trade;

//+------------------------------------------------------------------+
//|     variables                                                    |
//+------------------------------------------------------------------+
int LotDigits;  // initialized in OnInit
double myPoint; // initialized in OnInit
int MaxSlippage_;
int OrderWait = 5;   //# of seconds to wait if sending order returns error
int OrderRetry = 5;  //# of retries if sending order returns error
int MaxSlippage = 3; // slippage, adjusted in OnInit
double TradeSize = 0;
bool Hedging = false;
int MaxOpenTrades = 1000;
int MaxLongTrades = 1000;
int MaxShortTrades = 1000;
int MaxPendingOrders = 1000;
int MaxLongPendingOrders = 1000;
int MaxShortPendingOrders = 1000;

//+------------------------------------------------------------------+
//|     indicator handle                                             |
//+------------------------------------------------------------------+
int Spikedetector_handle;
double Spikedetector[];
double Spikedetector_12[];

//+------------------------------------------------------------------+
//|    trade management                                              |
//+------------------------------------------------------------------+
bool revengeMode = false;
double lastTradeLot = 0;
double lastMaxLot = 0;

//+------------------------------------------------------------------+
//|                                                                  |
//|             authorized logins                                    |
//|                                                                  |
//+------------------------------------------------------------------+
long LoginsArray[] = {
    3170564,
    3542835,  // hermann
    20323508, // darlin
    20203654  // darlin
};

//+------------------------------------------------------------------+
//|    includes                                                      |
//+------------------------------------------------------------------+
#include "headers/utils.mqh"
#include "headers/orderSend.mqh"
#include "headers/orderManagement.mqh"
#include "headers/lotCalculator.mqh"
#resource "\\Indicators\\TradingCode\\Spikedetector\\Spikedetector.ex5"
string indicator_name = "::Indicators\\TradingCode\\Spikedetector\\Spikedetector.ex5";

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   if (!MQLInfoInteger(MQL_TESTER))
   {
#include "headers/validityChecker.mqh"
   }

   TradeSize = tradeVolume;
   MaxSlippage_ = MaxSlippage;

   // initialize myPoint
   myPoint = Point();
   if (Digits() == 5 || Digits() == 3)
   {
      myPoint *= 10;
      MaxSlippage_ *= 10;
   }
   // initialize LotDigits
   double LotStep = SymbolInfoDouble(Symbol(), SYMBOL_VOLUME_STEP);

   if (NormalizeDouble(LotStep, 3) == round(LotStep))
      LotDigits = 0;
   else if (NormalizeDouble(10 * LotStep, 3) == round(10 * LotStep))
      LotDigits = 1;
   else if (NormalizeDouble(100 * LotStep, 3) == round(100 * LotStep))
      LotDigits = 2;
   else
      LotDigits = 3;

   Spikedetector_handle = iCustom(NULL, PERIOD_CURRENT, indicator_name, true, true, tradeType, false);

   if (Spikedetector_handle < 0)
   {
      Print("The creation of Spikedetector has failed: Spikedetector_handle=", INVALID_HANDLE);
      Print("Runtime error = ", GetLastError());
      return (INIT_FAILED);
   }
   return (INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason) {}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   static datetime candletime = 0;
   datetime time = iTime(NULL, PERIOD_CURRENT, 0);

   if (revengeMode)
   {
      MonitorRevenge();
   }
   else
      MonitorTrades();

   if (candletime != time)
   {
      ulong ticket = 0;
      double price;
      string comment = revengeMode ? programname + " - revenge mode" : programname;
      double MaxLot = 0;

      if (CopyBuffer(Spikedetector_handle, 0, 0, 200, Spikedetector) <= 0)
         return;
      ArraySetAsSeries(Spikedetector, true);

      if (CopyBuffer(Spikedetector_handle, 1, 0, 200, Spikedetector_12) <= 0)
         return;
      ArraySetAsSeries(Spikedetector_12, true);

      // Open Buy Order
      if (Spikedetector[1] != EMPTY_VALUE && Spikedetector[1] > NormalizeDouble(0, LotDigits) // Spikedetector >= fixed value
      )
      {
         MaxLot = LotCount(Symbol(), POSITION_TYPE_BUY, 1.0);
         candletime = time;
         MqlTick last_tick;
         SymbolInfoTick(Symbol(), last_tick);
         price = last_tick.ask;

         if (TerminalInfoInteger(TERMINAL_TRADE_ALLOWED) && MQLInfoInteger(MQL_TRADE_ALLOWED))
         {
            if (revengeMode)
            {
               TradeSize = lastTradeLot * martingalMultiplier;

               if (TradeSize > MaxLot)
               {
                  if (lastMaxLot <= 0)
                  {
                     lastMaxLot = lastTradeLot;
                  }
                  int numberOfTrade = TradeSize / lastMaxLot;

                  for (int j = 0; j < numberOfTrade; j++)
                  {
                     ticket = myOrderSend(ORDER_TYPE_BUY, price, lastMaxLot, comment);
                  }
                  lastTradeLot = TradeSize;
               }
               else
               {
                  ticket = myOrderSend(ORDER_TYPE_BUY, price, TradeSize, comment);
               }
            }
            else
            {
               ticket = myOrderSend(ORDER_TYPE_BUY, price, TradeSize, comment);
            }

            if (ticket == 0)
               return;
         }
         else // not autotrading => only send alert
            myAlert("order", "");
      }

      // Open Sell Order
      if (Spikedetector_12[1] != EMPTY_VALUE && Spikedetector_12[1] > NormalizeDouble(0, LotDigits) // Spikedetector >= fixed value
      )
      {
         MaxLot = LotCount(Symbol(), POSITION_TYPE_SELL, 1.0);
         candletime = time;
         MqlTick last_tick;
         SymbolInfoTick(Symbol(), last_tick);
         price = last_tick.bid;

         if (TerminalInfoInteger(TERMINAL_TRADE_ALLOWED) && MQLInfoInteger(MQL_TRADE_ALLOWED))
         {
            if (revengeMode)
            {
               TradeSize = lastTradeLot * martingalMultiplier;
               if (TradeSize > MaxLot)
               {
                  if (lastMaxLot <= 0)
                  {
                     lastMaxLot = lastTradeLot;
                  }
                  int numberOfTrade = TradeSize / lastMaxLot;
                  // for loop
                  for (int j = 0; j < numberOfTrade; j++)
                  {
                     ticket = myOrderSend(ORDER_TYPE_SELL, price, lastMaxLot, comment);
                  }
                  lastTradeLot = TradeSize;
               }
               else
               {
                  ticket = myOrderSend(ORDER_TYPE_SELL, price, TradeSize, comment);
               }
            }
            else
            {
               ticket = myOrderSend(ORDER_TYPE_SELL, price, TradeSize, comment);
            }

            if (ticket == 0)
               return;
         }
         else // not autotrading => only send alert
            myAlert("order", "");
      }
   }
}
//+------------------------------------------------------------------+
