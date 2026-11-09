#!/usr/bin/python3
# 
import pprint, json, threading, time, os, sys, stat, trace
import datetime, socket
import paho.mqtt.client as mqtt
import paho.mqtt.subscribe as subscribe
import dateutil.parser

topic = r"picofan/feeds/ProxFanPico"
broker = "192.168.1.135"
tmpSaveFile = r"/tmp/ProxFanPico.json"

userName = "<put data here>"
password = ""

hostname = socket.gethostname()
ip_address = socket.gethostbyname(hostname)
clientID = "proxmoxPoll.%s" % str(ip_address).split('.')[-1]
del hostname, ip_address
#print(clientID)

def with_timeout(func, timeout, *args, **kwargs):
    """
    Wrapper around a function call that enforces a timeout.
    
    Parameters:
    - func: The function to call.
    - timeout: Timeout in seconds.
    - args: Positional arguments to pass to the function.
    - kwargs: Keyword arguments to pass to the function.
    
    Returns:
    - The result of func if it completes before the timeout, otherwise None.
    """
    class ResultContainer(threading.Thread):
        def __init__(self, *args, **keywords):
            threading.Thread.__init__(self, *args, **keywords)
            self.result = None
            self.killed = False

        def start(self):
            self.__run_backup = self.run
            self.run = self.__run      
            threading.Thread.start(self)

        def __run(self):
            sys.settrace(self.globaltrace)
            self.__run_backup()
            self.run = self.__run_backup

        def globaltrace(self, frame, event, arg):
            if event == 'call':
              return self.localtrace
            else: return None

        def localtrace(self, frame, event, arg):
            if self.killed:
              if event == 'line':
                raise SystemExit()
            return self.localtrace

        def kill(self):
            self.killed = True

    #result_container = ResultContainer()
   
    #result_container = thread
    def target():
        thread.result = func(*args, **kwargs)

    thread = ResultContainer(target=target)
    
    #thread = threading.Thread(target=target)
    thread.start()
    thread.join(timeout)
    
    if thread.is_alive():
        thread.kill()
        time.sleep(0.12)
        thread.join()  # Wait for the thread to exit        
        return None
    else:
        #return result_container.result
        return thread.result

newData = True
msg = with_timeout(subscribe.simple, 0.250, topic, 0, hostname=broker, client_id=clientID, retained=True, clean_session=False, auth={'username' : userName, 'password' : password }, msg_count=1)
if msg is None: 
  #print("no data retained")

  newData = False
  if not os.path.exists( tmpSaveFile ):
     oldjson = "{}"
  else:
   with open(tmpSaveFile, 'r') as file1:
     oldjson = file1.read()

  pyObj = json.loads( oldjson )
  pyObj['oldData'] = 1
  pjson = json.dumps(pyObj, sort_keys=True, separators=(',', ':') )
  #pprint.pprint(pjson)
  print(pjson);
  exit(2)

#msg = client.subscribe.simple(topic, hostname=broker)
#pprint.pprint(msg)

#for msg in msgs:
#print("%s %s" % (msg.topic, str(msg.payload)))
pyObj = json.loads( msg.payload.decode() )
pyObj['client_id'] = clientID
pyObj['oldData'] = 0
#print('%s ' % msg.topic, end='') 
#pprint.pprint(pyObj)
pjson = json.dumps(pyObj, sort_keys=True, separators=(',', ':'))
#pprint.pprint(pjson)
print(pjson);

if not newData: exit(2)

creation_time = modification_time = None

with open(tmpSaveFile, "w") as file1:
    # Writing data to a file
    #file1.write( msg.payload.decode() )
    file1.write( pjson )

if os.path.exists( tmpSaveFile ):
  os.chmod( tmpSaveFile, stat.S_IWUSR | stat.S_IRUSR |  stat.S_IRGRP | stat.S_IROTH )
  if "date time" in pyObj:
    try:
      #frac = datetime.datetime.now().microsecond
      filedate = dateutil.parser.parse( pyObj["date time"] ).timestamp()
    except Exception as E:
      raise(E)
      exit(2)
    else:
      creation_time = modification_time = filedate
      os.utime( tmpSaveFile, (creation_time, modification_time) )  

#client.disconnect()
del subscribe

exit(0)