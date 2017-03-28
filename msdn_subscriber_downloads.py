#!/usr/bin/env python

# Uses an MSDN subscriber session cookie to download every possible file in the
# `idlist` range.  MSDN has no nice way to search for all entries so instead we
# brute force.
#
# As of 2017-03-28T15:00:00Z, the latest posted FileId was 71584.
# The number of actual entries (including deleted) was 31755.

import glob
import httplib
import itertools
import json
import os
import re
import sys
import threading
import time
from collections import OrderedDict
from multiprocessing.pool import ThreadPool
from threading import Lock


# program configuration
num_attempts_per_id     = 10
num_threads             = 64
max_id                  = 72000
min_id                  = 0
idlist                  = range(max_id, min_id, -1)
output_filename         = 'msdn_subscriber_downloads'
remove_attrs            = ['DownloadProvider', 'NotAuthorizedReasonId',
                              'IsAuthorization', 'BenefitLevels']
js_date_pattern         = re.compile('/Date\(([0-9]+)\)/')
iso8601_date_pattern    = '%FT%TZ'

# program strings
existing_results        = 'Pulled in %d existing results'
new_results_length      = '\nTotal results: %d'
status_str              = '\r<Thread %02d> downloading FileId %05d'
failure_msg             = '\n<Thread %02d> FAILED TO download FileId %05d'
exception_str           = '\n<Thread %02d> EXCEPTION(%05d): %s'
uncaught_exception_str  = '\n<Thread %02d> non-Exception EXCEPTION(%05d)'

# HTTP data
domain                  = 'msdn.microsoft.com'
path                    = '/en-us/subscriptions/securejson/GetFileSearchResult'
cookie_str              = "MY_MS_COOKIE"
headers                 =  {
    "Cookie":           cookie_str,
    "Origin":           "https://"+domain,
    "Accept-Encoding":  "",
    "Accept-Language":  "en-US,en;q=0.8",
    "User-Agent":       "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36" + \
                          " (KHTML, like Gecko) Chrome/40.0.2214.93" + \
                          " Safari/537.36",
    "Content-Type":     "application/json; charset=UTF-8",
    "Accept":           "application/json, text/javascript, */*; q=0.01",
    "Referer":          "https://"+domain+"/subscriptions/securedownloads/?",
    "X-Requested-With": "XMLHttpRequest",
    "Connection":       "keep-alive"
    }
post_data               = '{"Languages":"en","Architectures":"",' + \
                            '"ProductFamilyIds":"","FileExtensions":"",' + \
                            '"MyProducts":false,"ProductFamilyId":0,' + \
                            '"SearchTerm":"","Brand":"MSDN","PageIndex":0,' + \
                            '"PageSize":10000,"FileId":%d}'

# locks
sysout_lock  = Lock()
idlist_lock  = Lock()
results_lock = Lock()


def replace_old_date(old_date):
    if js_date_pattern.match(old_date):
        date_int = int(js_date_pattern.match(old_date).group(1))
        date_int /= 1000
        new_date_str = time.strftime(iso8601_date_pattern,
                time.gmtime(date_int))
        return new_date_str.decode()
    return old_date


def worker_thread(n):
    global idlist
    global results
    tls = threading.local()

    # open an SSL keep-alive connection
    tls.conn = httplib.HTTPSConnection(domain)

    # loop until none are left to download
    while len(idlist):
        # get an ID to retrieve
        idlist_lock.acquire()
        if len(idlist):
            tls.current_id = idlist.pop()
            idlist_lock.release()
        else:
            idlist_lock.release()
            break

        # print status
        sysout_lock.acquire()
        tls.status_str = status_str[:]
        sys.stdout.write(tls.status_str % (n, tls.current_id))
        sys.stdout.flush()
        sysout_lock.release()
        
        # attempt to get the ID num_attempts_per_id times
        tls.k       = 0
        tls.success = False
        while tls.k < num_attempts_per_id and not tls.success:
            try:
                tls.k += 1
                tls.conn.request('POST', path, post_data % tls.current_id,
                    headers)
                r1 = tls.conn.getresponse()
                response = r1.read()
                if response and len(response) > 0:
                    json_str =  json.loads(response)
                    if json_str and 'TotalResults' in json_str:
                        if json_str['TotalResults'] > 0:
                            ordered_json = json \
                              .JSONDecoder(object_pairs_hook=OrderedDict) \
                              .decode(response)
                            new_files = ordered_json['Files']
                            for new_file in new_files:
                                for attr in remove_attrs:
                                    if attr in new_file:
                                        new_file.pop(attr)
                                if 'PostedDate' in new_file:
                                    new_file['PostedDate'] = replace_old_date(new_file['PostedDate'])
                            results_lock.acquire()
                            for new_file in new_files:
                                if new_file not in results:
                                    results.append(new_file)
                            results_lock.release()
                        tls.success = True
                        break
            # abort attempt on any exception
            except Exception as e:
                sysout_lock.acquire()
                print exception_str % (n, tls.current_id, repr(e))
                sysout_lock.release()
                break
            except:
                sysout_lock.acquire()
                print uncaught_exception_str % (n, tls.current_id)
                sysout_lock.release()
                break

        # if failed to get after num_attempts_per_id times
        if tls.k == num_attempts_per_id and not tls.success:
            sysout_lock.acquire()
            print failure_msg % (n, tls.current_id)
            sysout_lock.release()

    # close connection
    tls.conn.close()
    return


if __name__ == '__main__':
    global results
    results = []

    # read existing results
    for fn in glob.glob(output_filename+'*.json'):
        f = open(fn, 'rb')
        d = f.read()
        f.close()
        #os.remove(fn)
        j = json \
          .JSONDecoder(object_pairs_hook=OrderedDict) \
          .decode(d)
        j = j['Files']
        results += j
    print existing_results % len(results)

    # Replace old dates
    for r in results:
        if 'PostedDate' in r:
            r['PostedDate'] = replace_old_date(r['PostedDate'])

    # kick off the threads to retrieve all FileIds
    threads = []
    for i in range(num_threads):
        t = threading.Thread(target=worker_thread, args=(i,))
        threads.append(t)
        t.start()

    # wait for all threads to finish
    for i in range(num_threads):
        threads[i].join()

    # sort results, prettify, output
    results = sorted(results, key=lambda x: x['FileId'])
    print new_results_length % len(results)
    for i in range(0, len(results)):
        results[i]['Sha1Hash'] = results[i]['Sha1Hash'].lower()
    for i in range(min_id, max_id, 500):
        f = open(output_filename + ('.%d-%d.json'%(i,i+499)), 'wb')
        t = filter(lambda x: x['FileId'] >= i and x['FileId'] < (i+500), results)
        f.write(json.dumps(OrderedDict([('Files', t)]),
            indent=2, separators=(',', ': ')))
        f.close()
