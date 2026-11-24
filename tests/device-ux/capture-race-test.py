#!/usr/bin/env python3
"""Run the firmware capture/worker handoff against a host thread scheduler."""
import pathlib, subprocess, sys, tempfile
s = (pathlib.Path(sys.argv[1]) / 'src/core/serialcmds.cpp').read_text()
packet = s[s.index('struct CmdPacket {'):s.index('bool parseSerialCommand(')]
capture = s[s.index('bool parseSerialCommandCapture('):s.index('\nvoid handleSerialCommands')]
a = s.index('            if (packet.capture) {', s.index('void handleSerialCommands'))
b = s.index('            Serial.println("COMMAND:', a)
worker = s[a:b]
pre = r'''
#include <chrono>
#include <condition_variable>
#include <cstring>
#include <deque>
#include <iostream>
#include <mutex>
#include <string>
#include <thread>
#include <cassert>
using namespace std::chrono_literals;
struct String : std::string { using std::string::string; String():std::string() {} };
struct Sem { std::mutex m; std::condition_variable cv; int value; Sem(int v):value(v){} };
using SemaphoreHandle_t=Sem*;
#define pdTRUE 1
#define portMAX_DELAY 0xffffffffU
#define pdMS_TO_TICKS(x) (x)
int xSemaphoreTake(Sem* s, unsigned ms) {
 std::unique_lock<std::mutex> l(s->m);
 if(ms==portMAX_DELAY) s->cv.wait(l,[&]{return s->value>0;});
 else if(!s->cv.wait_for(l,std::chrono::milliseconds(ms),[&]{return s->value>0;})) return 0;
 --s->value; return 1;
}
void xSemaphoreGive(Sem* s) { std::lock_guard<std::mutex> l(s->m); s->value=1; s->cv.notify_one(); }
struct SerialDevice { virtual void print(const String&)=0; virtual ~SerialDevice()=default; };
struct Sink:SerialDevice { void print(const String&) override {} } sink;
SerialDevice *serialDevice=&sink;
struct TeeSerialDevice:SerialDevice { SerialDevice *inner; String *cap;
 TeeSerialDevice(SerialDevice *s,String *c):inner(s),cap(c){}
 void print(const String &v) override {cap->append(v);inner->print(v);} };
Sem mtx(1),done(0),resultMtx(1);
SemaphoreHandle_t s_capMtx=&mtx,s_capDoneSem=&done,s_capResultMtx=&resultMtx;
String s_capResult; uint32_t s_capGeneration=0; bool s_capActive=false;
'''
post_packet = r'''
struct Queue { std::mutex m; std::condition_variable cv; std::deque<CmdPacket> q; } queue, replies;
Queue *cmdQueue=&queue,*rspQueue=&replies;
int xQueueSend(Queue *q,const CmdPacket *p,unsigned) { std::lock_guard<std::mutex> l(q->m);q->q.push_back(*p);q->cv.notify_one();return 1; }
int xQueueSend(Queue *,const bool *,unsigned) {return 1;}
struct Cli { bool parse(const String &cmd) { if(cmd=="slow") std::this_thread::sleep_for(100ms); else std::this_thread::sleep_for(35ms); serialDevice->print(cmd);return true; } } serialCli;
'''
main = r'''
void process(CmdPacket packet) { bool result=false;
''' + worker + r'''
(void)result; }
void workerLoop() { for(int i=0;i<2;++i) { CmdPacket packet;
 { std::unique_lock<std::mutex> l(queue.m); queue.cv.wait(l,[]{return !queue.q.empty();}); packet=queue.q.front();queue.q.pop_front(); }
 process(packet); } }
int main() { std::thread worker(workerLoop); String out;
 assert(!parseSerialCommandCapture("slow",out,20));
 assert(parseSerialCommandCapture("fast",out,500));
 assert(out=="fast"); worker.join(); std::cout << "Capture timeout isolation test passed\n"; }
'''
with tempfile.TemporaryDirectory() as d:
    path = pathlib.Path(d) / 'capture.cpp'
    path.write_text(pre + packet + post_packet + capture + main)
    exe = pathlib.Path(d) / 'capture-test'
    subprocess.run(['g++','-std=c++17','-pthread','-Wall','-Wextra','-Werror',str(path),'-o',str(exe)],check=True)
    subprocess.run([str(exe)],check=True)
