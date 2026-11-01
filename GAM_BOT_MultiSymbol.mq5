
//+------------------------------------------------------------------+
//| GAM BOT V1 - DERIV MT5                                           |
//| XAUUSD + BTCUSD | Maximum 5 simultaneous positions                |
//+------------------------------------------------------------------+
#property strict
#property version "1.00"

#include <Trade/Trade.mqh>
CTrade trade;

input string Symbols = "XAUUSD,BTCUSD";
input double Lots = 0.03;
input int MaxTrades = 5;
input int FastEMA = 50;
input int SlowEMA = 200;
input int RSIPeriod = 14;
input int ATRPeriod = 14;
input double StopATR = 2.0;
input double RewardRisk = 2.0;
input double MaxDailyLossPercent = 2.0;
input ulong Magic = 26110101;

string pairs[];
int fastH[], slowH[], rsiH[], atrH[];
datetime lastBar[];
int dayOfYear = -1;
double dayStartEquity = 0;

int OnInit()
{
   int n = StringSplit(Symbols, ',', pairs);
   if(n < 1) return INIT_FAILED;

   ArrayResize(fastH,n);
   ArrayResize(slowH,n);
   ArrayResize(rsiH,n);
   ArrayResize(atrH,n);
   ArrayResize(lastBar,n);

   trade.SetExpertMagicNumber(Magic);

   for(int i=0;i<n;i++)
   {
      StringTrimLeft(pairs[i]);
      StringTrimRight(pairs[i]);

      if(!SymbolSelect(pairs[i],true))
      {
         Print("Symbol unavailable: ",pairs[i]);
         return INIT_FAILED;
      }

      fastH[i]=iMA(pairs[i],PERIOD_M15,FastEMA,0,MODE_EMA,PRICE_CLOSE);
      slowH[i]=iMA(pairs[i],PERIOD_M15,SlowEMA,0,MODE_EMA,PRICE_CLOSE);
      rsiH[i]=iRSI(pairs[i],PERIOD_M15,RSIPeriod,PRICE_CLOSE);
      atrH[i]=iATR(pairs[i],PERIOD_M15,ATRPeriod);

      if(fastH[i]==INVALID_HANDLE ||
         slowH[i]==INVALID_HANDLE ||
         rsiH[i]==INVALID_HANDLE ||
         atrH[i]==INVALID_HANDLE)
         return INIT_FAILED;
   }

   dayStartEquity=AccountInfoDouble(ACCOUNT_EQUITY);
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(),dt);
   dayOfYear=dt.day_of_year;

   EventSetTimer(30);
   Print("GAM BOT V1 initialized.");
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   EventKillTimer();
   for(int i=0;i<ArraySize(pairs);i++)
   {
      IndicatorRelease(fastH[i]);
      IndicatorRelease(slowH[i]);
      IndicatorRelease(rsiH[i]);
      IndicatorRelease(atrH[i]);
   }
}

void OnTick(){}

void OnTimer()
{
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(),dt);

   if(dt.day_of_year!=dayOfYear)
   {
      dayOfYear=dt.day_of_year;
      dayStartEquity=AccountInfoDouble(ACCOUNT_EQUITY);
   }

   if(dayStartEquity>0 &&
      AccountInfoDouble(ACCOUNT_EQUITY)<=
      dayStartEquity*(1.0-MaxDailyLossPercent/100.0))
   {
      Print("GAM BOT: Daily loss limit reached. New entries stopped.");
      return;
   }

   if(CountPositions()>=MaxTrades) return;

   for(int i=0;i<ArraySize(pairs);i++)
   {
      if(CountPositions()>=MaxTrades) break;
      CheckPair(i);
   }
}

int CountPositions()
{
   int count=0;
   for(int i=PositionsTotal()-1;i>=0;i--)
   {
      ulong ticket=PositionGetTicket(i);
      if(ticket>0 && PositionGetInteger(POSITION_MAGIC)==(long)Magic)
         count++;
   }
   return count;
}

void CheckPair(int i)
{
   string s=pairs[i];

   MqlTick tick;
   if(!SymbolInfoTick(s,tick) || tick.bid<=0 || tick.ask<=0)
      return;

   datetime bar=iTime(s,PERIOD_M15,0);
   if(bar==0 || bar==lastBar[i]) return;
   lastBar[i]=bar;

   // One position per symbol.
   if(PositionSelect(s)) return;

   double f1[],f2[],sl1[],sl2[],r[],a[];
   ArraySetAsSeries(f1,true);
   ArraySetAsSeries(f2,true);
   ArraySetAsSeries(sl1,true);
   ArraySetAsSeries(sl2,true);
   ArraySetAsSeries(r,true);
   ArraySetAsSeries(a,true);

   if(CopyBuffer(fastH[i],0,1,1,f1)!=1) return;
   if(CopyBuffer(fastH[i],0,2,1,f2)!=1) return;
   if(CopyBuffer(slowH[i],0,1,1,sl1)!=1) return;
   if(CopyBuffer(slowH[i],0,2,1,sl2)!=1) return;
   if(CopyBuffer(rsiH[i],0,1,1,r)!=1) return;
   if(CopyBuffer(atrH[i],0,1,1,a)!=1) return;

   bool buy=(f2[0]<=sl2[0] && f1[0]>sl1[0] && r[0]>=50);
   bool sell=(f2[0]>=sl2[0] && f1[0]<sl1[0] && r[0]<=50);

   if(!buy && !sell) return;
   if(a[0]<=0) return;

   double minLot=SymbolInfoDouble(s,SYMBOL_VOLUME_MIN);
   double maxLot=SymbolInfoDouble(s,SYMBOL_VOLUME_MAX);
   double step=SymbolInfoDouble(s,SYMBOL_VOLUME_STEP);

   if(step<=0 || Lots<minLot || Lots>maxLot)
   {
      Print("Invalid requested volume for ",s);
      return;
   }

   double volume=minLot+
      MathFloor((Lots-minLot)/step+0.5)*step;

   int digits=(int)SymbolInfoInteger(s,SYMBOL_DIGITS);
   double point=SymbolInfoDouble(s,SYMBOL_POINT);
   double minStop=SymbolInfoInteger(s,SYMBOL_TRADE_STOPS_LEVEL)*point;
   double distance=MathMax(a[0]*StopATR,minStop+2*point);

   trade.SetTypeFillingBySymbol(s);

   if(buy)
   {
      double stop=NormalizeDouble(tick.ask-distance,digits);
      double target=NormalizeDouble(tick.ask+distance*RewardRisk,digits);
      if(!trade.Buy(volume,s,0,stop,target,"GAM BUY"))
         Print("BUY failed: ",trade.ResultRetcodeDescription());
   }

   if(sell)
   {
      double stop=NormalizeDouble(tick.bid+distance,digits);
      double target=NormalizeDouble(tick.bid-distance*RewardRisk,digits);
      if(!trade.Sell(volume,s,0,stop,target,"GAM SELL"))
         Print("SELL failed: ",trade.ResultRetcodeDescription());
   }
}
//+------------------------------------------------------------------+
