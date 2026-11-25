#include <cassert>
#include <cstdint>
#include <cstdlib>
#include <cstring>
#include <cstdio>
#include <string>
#include <map>
#include <functional>
#include <vector>
#include <iostream>
#include <algorithm>
#include <atomic>
using std::min;
class String {
    std::string x;
public:
    String() = default; String(const char *s):x(s?s:""){} String(const std::string &s):x(s){} String(unsigned long n):x(std::to_string(n)){}
    const char *c_str() const { return x.c_str(); } size_t length() const { return x.size(); }
    bool isEmpty() const { return x.empty(); } char operator[](size_t n) const {return x[n];}
    void replace(const char *a,const char *b) {size_t p=0; while ((p=x.find(a,p))!=std::string::npos) { x.replace(p,strlen(a),b); p+=strlen(b); }}
    bool operator==(const char *s) const {return x==s;} std::string str() const {return x;}
    friend String operator+(const String&a,const String&b) {return a.x+b.x;}
    friend String operator+(const char*a,const String&b) {return String(a)+b;}
    String &operator+=(const String &o) { x += o.x; return *this; }
    String &operator+=(const char *s) { x += (s?s:""); return *this; }
    friend String operator+(const String&a,const char*b) {return a+String(b);}
};
struct AsyncWebHeader { String val; String value() const{return val;} };
struct AsyncWebServerResponse { int code; String text; void addHeader(const char*,const char*){} };
struct AsyncWebServerRequest {
    void *_tempObject=nullptr; bool auth=true; int code=0; String text; std::map<std::string,String> args; std::map<std::string,AsyncWebHeader> headers;
    std::function<void()> disconnect;
    bool hasArg(const char *s) {return args.count(s); } String arg(const char*s) {return args[s];}
    bool hasHeader(const char*s) {return headers.count(s);} AsyncWebHeader *getHeader(const char*s) {return &headers[s];}
    void onDisconnect(std::function<void()> f){disconnect=f;}
    void send(int c,const char*,const String &v){code=c;text=v;}
    AsyncWebServerResponse *beginResponse(int c,const char*,const String &v){return new AsyncWebServerResponse{c,v};}
    void send(AsyncWebServerResponse *r){code=r->code;text=r->text; delete r;}
    void close(){if(disconnect)disconnect(); if(_tempObject){free(_tempObject);_tempObject=nullptr;}}
};
using Req = std::function<void(AsyncWebServerRequest*)>;
using Upload = std::function<void(AsyncWebServerRequest*,String,size_t,uint8_t*,size_t,bool)>;
using Body = std::function<void(AsyncWebServerRequest*,uint8_t*,size_t,size_t,size_t)>;
struct Route {Req req; Upload upload; Body body;};
struct Server {std::map<std::string,Route> routes; void on(const char *url,int method,Req r,Upload u=nullptr,Body b=nullptr){routes[std::string(url)+std::to_string(method)]={r,u,b};}} instance,*server=&instance;
#define HTTP_GET 0
#define HTTP_POST 1
#define U_FLASH 0
#define UPDATE_SIZE_UNKNOWN 0
#define CONFIG_ESP_DEFAULT_CPU_FREQ_MHZ 240
#define WIFI_PS_NONE 0
#define NULL_TASK nullptr
#define pdPASS 1
#define pdMS_TO_TICKS(x) (x)
#define PROGMEM
struct Partition {size_t size=0x400000;}; using esp_partition_t=Partition;
Partition partition;
const esp_partition_t *esp_ota_get_next_update_partition(void*){return &partition;}
bool isDualBootOtaProtected(const esp_partition_t*){return false;}
String humanReadableSize(size_t){return "4 MB";}
String jsonEscape(const String &s){return s;}
bool checkUserWebAuth(AsyncWebServerRequest *r,bool=false){if(!r->auth){r->send(401,"text/plain","Unauthorized");return false;}return true;}
bool isWebSessionValid(AsyncWebServerRequest*r){return r->auth;}
struct UpdateStub {bool active=false; int aborts=0,writes=0; bool beginFails=false; std::vector<uint8_t> contents;
 bool begin(size_t,int){if(beginFails) return false; active=true; contents.clear();return true;}
 void abort(){active=false;aborts++;}
 size_t write(uint8_t *p,size_t n){assert(active);contents.insert(contents.end(),p,p+n);writes++;return n;}
 bool end(bool){active=false;return true;} bool hasError(){return false;} const char* errorString(){return "error";}
} Update;
uint32_t nowMs=100; uint32_t millis(){return nowMs;} uint32_t esp_random(){static uint32_t i;return ++i;}
void setCpuFrequencyMhz(int){} struct WifiStub {void setSleep(int){}} WiFi;
static bool restartFails=false;
void applyPowerProfile(bool){}
// The OTA start now runs on its own task, which is what keeps /ota/begin from
// blocking the page. The stub can either run it inline (the usual case) or leave
// it pending so the test can look at both states.
static void(*s_beginTask)(void*)=nullptr;
static bool beginSpawnFails=false, beginDeferred=false;
static void *s_pendingBeginArg=nullptr;
static void runPendingBegin(){ if(s_beginTask&&s_pendingBeginArg){ void *a=s_pendingBeginArg; s_pendingBeginArg=nullptr; s_beginTask(a);} }
int xTaskCreate(void(*fn)(void*),const char*,int,void*pv,int,void*) {
  if(fn!=s_beginTask) return restartFails ? 0 : pdPASS;   // restart / other tasks
  if(beginSpawnFails) return 0;
  if(beginDeferred){ s_pendingBeginArg=pv; return pdPASS; }
  fn(pv);
  return pdPASS;
}
int vTaskDelete(void*){return 0;}
void vTaskDelay(int){} void delayedRestartTask(void*){}
const char *kOtaPageHtml="";
static constexpr size_t kOtaChunkCap=32*1024; static constexpr uint32_t kOtaIdleTimeoutMs=90000;
static std::atomic<bool> s_otaInProgress{false};
static bool s_otaScreenDirty=false, s_otaScreenDone=false, s_otaValid=false,s_wifiSwitchBusy=false, s_otaRestartPending=false;
static std::atomic<uint32_t> s_otaLastActivityMs{0}; static uint32_t s_otaEpoch=0; static size_t s_otaTotal=0,s_otaWritten=0,s_otaLegacyBufLen=0;
static uint8_t s_otaScreenPct=0,s_otaLegacyBuf[4096]; static uint8_t *s_otaChunkBuf=nullptr; static String s_otaError="";
static char s_otaSession[33]={}; static AsyncWebServerRequest *s_otaChunkOwner=nullptr,*s_otaLegacyOwner=nullptr;
static volatile bool s_otaAbortRequested=false;
static constexpr uint32_t kOtaIdleTimeoutNoDataMs=30000;
enum OtaBeginState : uint8_t { OTA_BEGIN_IDLE=0, OTA_BEGIN_PREPARING, OTA_BEGIN_READY, OTA_BEGIN_FAILED };
static volatile uint8_t s_otaBeginState=OTA_BEGIN_IDLE;
static char s_otaBeginErr[80]={0};
static volatile uint32_t s_otaBeginStartMs=0;
static volatile bool s_otaBeginCancel=false;
static constexpr uint32_t kOtaBeginTimeoutMs=180000UL;
// Mirrors webInterface.cpp: a session with no bytes yet expires quickly, a live
// transfer keeps the longer write timeout.
bool isOtaInProgress(){
  if(!s_otaInProgress) return false;
  if(s_otaBeginState==OTA_BEGIN_PREPARING) return (uint32_t)(millis()-s_otaBeginStartMs)<=kOtaBeginTimeoutMs;
  const uint32_t idle=(uint32_t)(millis()-s_otaLastActivityMs);
  if(s_otaWritten==0) return idle<=kOtaIdleTimeoutNoDataMs;
  return idle<=kOtaIdleTimeoutMs;
}
void otaUiPublish(){} void otaFreeBuf(){free(s_otaChunkBuf);s_otaChunkBuf=nullptr;}
bool otaAllocChunkBuf(){s_otaChunkBuf=(uint8_t*)malloc(kOtaChunkCap);return s_otaChunkBuf;}
#include "lifecycle.inc"
#include "match.inc"
void installRoutes() {
s_beginTask = otaBeginTask;
#include "routes.inc"
}
void token(AsyncWebServerRequest &r,const std::string &t){r.headers["X-OTA-Session"]={String(t)};}
int main(){
 installRoutes(); auto &begin=server->routes["/ota/begin1"]; auto &chunk=server->routes["/ota/chunk1"]; auto &abort=server->routes["/ota/abort1"]; auto &commit=server->routes["/ota/commit1"]; auto &legacy=server->routes["/ota1"];
 AsyncWebServerRequest invalid; invalid.args["size"]="65536junk"; begin.req(&invalid); assert(invalid.code==400 && !s_otaInProgress);
 // A /ota/begin with no following chunk must stop counting as "OTA in progress"
 // quickly: while it does, the device holds the OTA screen and answers no buttons.
 {AsyncWebServerRequest idleBegin; idleBegin.args["size"]="65536"; nowMs+=1000; begin.req(&idleBegin);
  assert(idleBegin.code==200 && s_otaInProgress);
  nowMs+=kOtaIdleTimeoutNoDataMs+1; assert(!isOtaInProgress());
  // The "transfer is active" state must have lapsed, so a new session may start.
  AsyncWebServerRequest takeOver; takeOver.args["size"]="65536"; begin.req(&takeOver);
  assert(takeOver.code==200 && s_otaInProgress);
  AsyncWebServerRequest dropIdle; token(dropIdle,std::string(s_otaSession)); abort.req(&dropIdle);
  assert(dropIdle.code==200 && !s_otaInProgress);
  Update.aborts = 0; // the scenarios below assert on aborts from here on
 }
 AsyncWebServerRequest a; a.args["size"]="65536"; begin.req(&a); assert(a.code==200 && s_otaInProgress); std::string session=s_otaSession;
 AsyncWebServerRequest other; other.args["size"]="65536"; begin.req(&other); assert(other.code==409 && Update.aborts==0 && session==s_otaSession);
 AsyncWebServerRequest wrong; token(wrong,"wrong"); abort.req(&wrong); assert(wrong.code==409 && Update.aborts==0);
 std::vector<uint8_t> data(64,0x55); data[0]=0xe9; data[32]=0x32;data[33]=0x54;data[34]=0xcd;data[35]=0xab;
 AsyncWebServerRequest c; token(c,session); c.args["offset"]="0"; chunk.body(&c,data.data(),32,0,64); assert(s_otaChunkOwner==&c);
 AsyncWebServerRequest d; token(d,session);d.args["offset"]="0";chunk.body(&d,data.data(),32,0,64);chunk.req(&d);assert(d.code==503 && s_otaChunkOwner==&c);
 chunk.body(&c,data.data()+32,32,32,64);chunk.req(&c);assert(c.code==200 && s_otaWritten==64 && Update.contents==data && !s_otaChunkOwner);
 AsyncWebServerRequest dup;token(dup,session);dup.args["offset"]="0";chunk.body(&dup,data.data(),64,0,64);chunk.req(&dup);assert(dup.code==200 && Update.writes==1);
 AsyncWebServerRequest unauth;unauth.auth=false;legacy.upload(&unauth,"bad",0,data.data(),64,true);legacy.req(&unauth);assert(unauth.code==401 && s_otaValid && s_otaWritten==64);
 AsyncWebServerRequest legacyOther;legacy.upload(&legacyOther,"bad",0,data.data(),64,true);legacy.req(&legacyOther);assert(legacyOther.code==400 && s_otaValid && Update.aborts==0);
 AsyncWebServerRequest partial;token(partial,session);partial.args["offset"]="64";chunk.body(&partial,data.data(),32,0,64);assert(s_otaChunkOwner==&partial);partial.close();assert(!s_otaChunkOwner);
 AsyncWebServerRequest stale;token(stale,session);stale.args["offset"]="64";chunk.body(&stale,data.data(),32,0,64);assert(s_otaChunkOwner==&stale);
 AsyncWebServerRequest cancel;token(cancel,session);abort.req(&cancel);assert(cancel.code==200 && !s_otaInProgress);
 AsyncWebServerRequest fresh;fresh.args["size"]="65536";begin.req(&fresh);assert(fresh.code==200 && session!=s_otaSession);
 chunk.body(&stale,data.data()+32,32,32,64);chunk.req(&stale);assert(stale.code==400 && s_otaWritten==0);stale.close();
 AsyncWebServerRequest badAbort;token(badAbort,session);abort.req(&badAbort);assert(badAbort.code==409 && s_otaInProgress);
 AsyncWebServerRequest badCommit;token(badCommit,session);commit.req(&badCommit);assert(badCommit.code==409 && s_otaInProgress);
 nowMs+=90001;AsyncWebServerRequest recover;recover.args["size"]="65536";begin.req(&recover);assert(recover.code==200 && s_otaInProgress && !s_otaAbortRequested);
 std::string current=s_otaSession;
 std::vector<uint8_t> big(32768,0x55); big[0]=0xe9;big[32]=0x32;big[33]=0x54;big[34]=0xcd;big[35]=0xab;
 AsyncWebServerRequest first;token(first,current);first.args["offset"]="0";chunk.body(&first,big.data(),big.size(),0,big.size());chunk.req(&first);assert(first.code==200);
 AsyncWebServerRequest second;token(second,current);second.args["offset"]="32768";chunk.body(&second,big.data(),big.size(),0,big.size());chunk.req(&second);assert(second.code==200 && s_otaWritten==65536);
 restartFails=true;AsyncWebServerRequest final;token(final,current);commit.req(&final);
 assert(final.code==200 && final.text.str().find("\"restartScheduled\":false")!=std::string::npos && !s_otaRestartPending && !s_otaInProgress);
 AsyncWebServerRequest legacyOk;legacy.upload(&legacyOk,"ota.bin",0,data.data(),data.size(),true);legacy.req(&legacyOk);
 assert(legacyOk.code==200 && legacyOk.text.str().find("\"restartScheduled\":false")!=std::string::npos && !s_otaInProgress);legacyOk.close();
 // On-device cancel: while the OTA screen is up a held key only sets a flag. The
 // UI task must never call Update.abort()/otaReleaseLock() itself -- the AsyncTCP
 // task may still be writing into the chunk buffer. The next chunk request owns
 // the teardown, answers 409 and frees the buffer there.
 AsyncWebServerRequest reopen; reopen.args["size"]="65536"; begin.req(&reopen);
 assert(reopen.code==200 && s_otaInProgress && !s_otaAbortRequested);
 std::string cancelSession=s_otaSession;
 s_otaAbortRequested=true;
 AsyncWebServerRequest cancelled;token(cancelled,cancelSession);cancelled.args["offset"]="0";
 chunk.body(&cancelled,big.data(),big.size(),0,big.size());chunk.req(&cancelled);
 assert(cancelled.code==409 && !s_otaInProgress && !s_otaAbortRequested && !s_otaChunkBuf);
 // A stale chunk from the cancelled session may not resurrect it.
 AsyncWebServerRequest resurrection;token(resurrection,cancelSession);resurrection.args["offset"]="0";
 chunk.body(&resurrection,big.data(),big.size(),0,big.size());chunk.req(&resurrection);
 assert(resurrection.code==400 && !s_otaInProgress && s_otaWritten==0);
 // --- Starting a transfer must never block the HTTP reply -------------------
 // The browser used to sit on "Initializing OTA slot..." because Update.begin()
 // ran inside the /ota/begin request. It now answers immediately with
 // pending:true and the outcome is polled from /ota/ready.
 auto &ready=server->routes["/ota/ready0"];
 beginDeferred=true;
 {AsyncWebServerRequest slow; slow.args["size"]="65536"; nowMs+=1000;
  begin.req(&slow);
  assert(slow.code==200 && slow.text.str().find("\"pending\":true")!=std::string::npos);
  assert(slow.text.str().find("\"chunkSize\":32768")!=std::string::npos);
  assert(slow.text.str().find("\"session\":\"")!=std::string::npos);
  // The request is answered while the slot is still being prepared, and the
  // "in progress" state must not lapse into the fast "no bytes yet" timeout.
  assert(s_otaBeginState==OTA_BEGIN_PREPARING && s_otaInProgress);
  nowMs+=kOtaIdleTimeoutNoDataMs+5000; assert(isOtaInProgress());
  AsyncWebServerRequest whilePreparing; whilePreparing.args["size"]="65536"; begin.req(&whilePreparing);
  assert(whilePreparing.code==409); // one transfer at a time, even mid-start
  AsyncWebServerRequest poll; ready.req(&poll);
  assert(poll.code==200 && poll.text.str().find("\"state\":\"preparing\"")!=std::string::npos);
  // A chunk may never be written before the slot exists.
  const int writesBefore=Update.writes;
  AsyncWebServerRequest early; token(early,std::string(s_otaSession)); early.args["offset"]="0";
  chunk.body(&early,big.data(),big.size(),0,big.size()); chunk.req(&early);
  assert(early.code==409 && s_otaValid==false && Update.writes==writesBefore);
  runPendingBegin();
  assert(s_otaBeginState==OTA_BEGIN_READY && s_otaValid && Update.active);
  ready.req(&poll);
  assert(poll.code==200 && poll.text.str().find("\"state\":\"ready\"")!=std::string::npos);
  AsyncWebServerRequest afterReady; token(afterReady,std::string(s_otaSession)); afterReady.args["offset"]="0";
  chunk.body(&afterReady,big.data(),big.size(),0,big.size()); chunk.req(&afterReady);
  assert(afterReady.code==200);
  AsyncWebServerRequest stop; token(stop,std::string(s_otaSession)); abort.req(&stop);
  assert(stop.code==200 && !s_otaInProgress);
 }
 // A start that fails must report the reason to /ota/ready and free everything,
 // instead of leaving the page (and the device screen) waiting forever.
 beginDeferred=false;
 {Update.beginFails=true;
  AsyncWebServerRequest bad; bad.args["size"]="65536"; begin.req(&bad);
  assert(bad.code==200); // answered immediately, failure arrives via /ota/ready
  assert(s_otaBeginState==OTA_BEGIN_FAILED && !s_otaInProgress && !s_otaChunkBuf);
  AsyncWebServerRequest poll; ready.req(&poll);
  assert(poll.code==200 && poll.text.str().find("\"state\":\"failed\"")!=std::string::npos);
  assert(poll.text.str().find("\"msg\":\"error\"")!=std::string::npos);
  Update.beginFails=false;
 }
 // If the worker task cannot even be created, /ota/begin must say so at once.
 {beginSpawnFails=true;
  AsyncWebServerRequest noTask; noTask.args["size"]="65536"; begin.req(&noTask);
  assert(noTask.code==503 && !s_otaInProgress && !s_otaChunkBuf);
  AsyncWebServerRequest poll; ready.req(&poll);
  assert(poll.text.str().find("\"state\":\"failed\"")!=std::string::npos);
  beginSpawnFails=false;
 }
 std::cout<<"OTA route ownership, stale-session, retry, timeout, cancel and restart tests passed\n";
}
