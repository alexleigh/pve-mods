#!/usr/bin/env python3
#
import pprint, json, time, os, sys, stat, trace
import datetime, re, subprocess
import dateutil.parser

templateSaveFile = r"/tmp/smartctl.%s.json"
mounts = None

with open("/proc/mounts", "r") as f:
  mounts = [line.rstrip() for line in f] 

creation_time = modification_time = pyObj = None  

#pprint.pprint(mounts)
nvmRe = re.compile( r"^(.+nvme\d.\d)p\d+\s+(.boot\S+)", re.I )
for line in mounts:
  nvmem = nvmRe.match(line)
  if nvmem:
    (nvme, mntpt) = nvmem.group(1,2)
    bnvme = nvme.split('/')[-1]

    #print('nvme=%s mntpt=%s bnvme=%s' % (nvme, mntpt, bnvme) )
    jsonStr = subprocess.run(['/usr/sbin/smartctl', '-a', nvme, '-j'], stdout=subprocess.PIPE).stdout.decode('utf-8') 
    #pprint.pprint(json)
    pyObj = json.loads( jsonStr )

    if ('local_time' in pyObj) and \
       ('asctime' in pyObj['local_time'] ) :
      pyObj['datetime'] = pyObj['local_time']['asctime']
      try:
        filedate = dateutil.parser.parse( pyObj["datetime"] ).timestamp()
        if 'time_t' in pyObj['local_time']: filedate = pyObj['local_time']['time_t']
      except Exception as E:
        pprint.pprint(E)
        pass
      else:
        creation_time = modification_time = filedate

    #pprint.pprint(pyObj)

    pjson = json.dumps(pyObj, sort_keys=True, separators=(',', ':'))
    #pprint.pprint(pjson)

    tmpSaveFile = templateSaveFile % bnvme

    with open(tmpSaveFile, "w") as file1:
      file1.write( pjson )

    if os.path.exists( tmpSaveFile ):
      os.chmod( tmpSaveFile, stat.S_IWUSR | stat.S_IRUSR |  stat.S_IRGRP | stat.S_IROTH )
      if creation_time and modification_time:
        os.utime( tmpSaveFile, (creation_time, modification_time) )  

    if 'nvme_smart_health_information_log' not in pyObj: 
      raise FileNotFoundError( 'nvme_smart_health_information_log does not exist' )
    
    if 'percentage_used' not in pyObj['nvme_smart_health_information_log']: 
      raise FileNotFoundError( 'percentage_used does not exist' )
    
    break

#pprint.pprint(pyObj)
if ('smartctl' in pyObj) and \
   ('exit_status' in pyObj['smartctl'] ): sys,exit( pyObj['smartctl']['exit_status']  )

sys.exit(38)

#/usr/sbin/smartctl -j -a /dev/nvme0n1 > /tmp/smartctl.nvme0n1.json
#chmod 744 /tmp/smartctl.nvme0n1.json
#exit $?
