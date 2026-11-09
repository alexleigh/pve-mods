#!/usr/bin/env python3
#
import pprint, json, time, os, sys, stat, trace
import datetime, re, subprocess, io
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


def getSwapNvmes():
  swapProcess = subprocess.Popen(['swapon', '-s'], stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
  stdout, stderr = swapProcess.communicate()
  if swapProcess.returncode != 0: raise subprocess.SubprocessError( stderr )

  bnvme = mdev = None

  #pprint.pprint(stdout)

  nvmRe = re.compile( r"^(.dev.+md\d+)(p\d+)\s+(.+)$", re.I )
  for line in stdout.splitlines():
    #print(line)
    nvmem = nvmRe.match(line)
    if nvmem:
      (nvme, rest) = nvmem.group(1,2)
      mdev = nvme
      bnvme = nvme.split('/')[-1]
      #print('nvme=%s rest=%s bnvme=%s' % (nvme, rest, bnvme) )
      break
  
  if mdev is None: raise FileNotFoundError( 'Unable to detect swap raid dev')
  del swapProcess
  
  mdadmProcess = subprocess.Popen(['mdadm', '-v', '--detail', '--scan', mdev], stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
  stdout, stderr = mdadmProcess.communicate()
  if mdadmProcess.returncode != 0: raise subprocess.SubprocessError( stderr )

  nvmes = []
  nvmRe = re.compile( r".*devices=(.dev.+nvme\d+.+),*", re.I )
  for line in stdout.splitlines():
    nvmem = nvmRe.match(line)
    if nvmem:
      nvmes = nvmem.group(1).strip().split(',')
      #pprint.pprint(nvmes)
      
  if len( nvmes ) < 1: raise ValueError( 'no nvmes found: %s' % str(nvmes) )

  creation_time = modification_time = None  

  pyObj = {}
  for nvme in nvmes:
    jsonStr = subprocess.run(['/usr/sbin/smartctl', '-a', nvme, '-j'], stdout=subprocess.PIPE).stdout.decode('utf-8') 
    #pprint.pprint(json)
    pyObj[nvme] = json.loads( jsonStr )

    if ('local_time' in pyObj[nvme]) and \
       ('asctime' in pyObj[nvme]['local_time'] ) :
      pyObj[nvme]['datetime'] = pyObj[nvme]['local_time']['asctime']
      try:
        filedate = dateutil.parser.parse( pyObj[nvme]["datetime"] ).timestamp()
        if 'time_t' in pyObj[nvme]['local_time']: filedate = pyObj[nvme]['local_time']['time_t']
      except Exception as E:
        pprint.pprint(E)
        pass
      else:
        creation_time = modification_time = filedate

    if 'nvme_smart_health_information_log' not in pyObj[nvme]: 
      raise KeyError( 'nvme_smart_health_information_log does not exist in [%s]' % nvme )
    
    if 'percentage_used' not in pyObj[nvme]['nvme_smart_health_information_log']: 
      raise KeyError( 'percentage_used does not exist in [%s]' % nvme )

  #pprint.pprint( pyObj )

  pjson = json.dumps(pyObj, sort_keys=True, separators=(',', ':'))
  tmpSaveFile = templateSaveFile % mdev.replace(r'/','')

  with open(tmpSaveFile, "w") as file1:
      file1.write( pjson )

  if os.path.exists( tmpSaveFile ):
      os.chmod( tmpSaveFile, stat.S_IWUSR | stat.S_IRUSR |  stat.S_IRGRP | stat.S_IROTH )
      if creation_time and modification_time:
        os.utime( tmpSaveFile, (creation_time, modification_time) )


getSwapNvmes()

#pprint.pprint(pyObj)
if ('smartctl' in pyObj) and \
   ('exit_status' in pyObj['smartctl'] ): sys.exit( pyObj['smartctl']['exit_status']  )

sys.exit(38)

#/usr/sbin/smartctl -j -a /dev/nvme0n1 > /tmp/smartctl.nvme0n1.json
#chmod 744 /tmp/smartctl.nvme0n1.json
#exit $?
