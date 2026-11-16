# Read-only invalid-link probes against the isolated test Auth service.
import urllib.request,urllib.error,urllib.parse,json
ref='https://ohkpvuhzvshjglbqyepq.supabase.co'
class NoRedirect(urllib.request.HTTPRedirectHandler):
 def redirect_request(self,*args,**kwargs): return None
opener=urllib.request.build_opener(NoRedirect())
results=[]
for label,extra in [('default_site_url',{}),('unlisted_destination',{'redirect_to':'https://r8-unlisted.invalid/recovery/'})]:
 query={'token':'0'*64,'type':'recovery',**extra}
 try:
  r=opener.open(ref+'/auth/v1/verify?'+urllib.parse.urlencode(query),timeout=20)
  status=r.status; location=r.headers.get('Location','')
 except urllib.error.HTTPError as e:
  status=e.code; location=e.headers.get('Location','')
 u=urllib.parse.urlsplit(location)
 safe_url=urllib.parse.urlunsplit((u.scheme,u.netloc,u.path,'','')) if location else None
 fields=urllib.parse.parse_qs(u.fragment or u.query)
 result={'probe':label,'http_status':status,'redirect_base':safe_url,'error_code':fields.get('error_code',[None])[0]}
 results.append(result);print(json.dumps(result))
assert all(r['http_status'] == 303 and r['redirect_base'] == 'https://monob26.github.io/history-teacher-dashboard-test/' and r['error_code'] == 'otp_expired' for r in results), 'Unexpected invalid-link redirect behaviour'
