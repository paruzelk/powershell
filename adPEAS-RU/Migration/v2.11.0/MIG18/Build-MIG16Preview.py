import argparse,hashlib,json,re,zipfile
from pathlib import Path
NAMES=['ruMIG2Technical','ruMIG2CheckDetails','ruMIG1Titles','ruMIG14RemediationLabels']
# Exact phrases in translated UI text only, not command code, names, keys or reference URLs.
RULES=[
('LDAP Channel Binding — привязки аутентификации LDAP к защищённому каналу TLS','привязки аутентификации LDAP к защищённому каналу TLS (LDAP Channel Binding)'),
('LDAP Channel Binding на контроллерах домена','привязку канала LDAP на контроллерах домена'),
('подписи LDAP и LDAP Channel Binding.','подписи LDAP и привязки канала LDAP.'),
('и LDAP Channel Binding.','и привязка канала LDAP.'),
('значение LDAP Channel Binding','значение параметра привязки канала LDAP'),
('Настроить LDAP Channel Binding через','Настроить привязку канала LDAP через'),
('и Channel Binding,','и привязку канала,'),
('и Group Policy Preferences применяются','и предпочтений групповой политики (GPP) применяются'),
('например Scripts или Group Policy Preferences.','например сценарии (Scripts) или предпочтения групповой политики (GPP).'),
('вредоносный файл Registry.pol, Scripts или Group Policy Preferences','вредоносный файл Registry.pol, сценарий (Scripts) или файл предпочтений групповой политики (GPP)'),
('задания, Group Policy Preferences или реестр','задания, предпочтения групповой политики (GPP) или реестр'),
('из Group Policy Preferences (Registry.xml, а не Administrative Templates)','из предпочтений групповой политики (GPP; Registry.xml, а не административные шаблоны)'),
('через Group Policy Preferences без','через предпочтения групповой политики (GPP) без'),
('пароли Group Policy Preferences,','пароли в предпочтениях групповой политики (GPP),'),
('Пароли Group Policy Preferences (GPP)','Пароли в предпочтениях групповой политики (GPP)'),
('файлах Group Policy Preferences','файлах предпочтений групповой политики (GPP)'),
('через Group Policy Preferences','через предпочтения групповой политики (GPP)'),
('Registry.xml (Group Policy Preferences)','Registry.xml (предпочтения групповой политики, GPP)'),
('включены механизмы Credential Roaming','включены механизмы перемещения учётных данных (Credential Roaming)'),
('Отключите Credential Roaming там, где оно','Отключите перемещение учётных данных там, где оно'),
('отключите Credential Roaming там, где оно','отключите перемещение учётных данных там, где оно'),
('Атрибуты Credential Roaming с','Атрибуты перемещаемых учётных данных с'),
('Чтение атрибутов Credential Roaming делегировано','Чтение атрибутов перемещаемых учётных данных делегировано'),
('Credential Roaming копирует','Механизм перемещения учётных данных (Credential Roaming) копирует'),
('материала Credential Roaming. Он либо','перемещаемых учётных данных. Этот механизм либо'),
('материала Credential Roaming','перемещаемых учётных данных'),
('скрипт развёртывания Credential Roaming','скрипт развёртывания механизма перемещения учётных данных'),
('перенесённый материал Credential Roaming','перемещаемые учётные данные'),
('Credential Roaming:','Перемещаемые учётные данные:'),
('Параметры Point and Print позволяют','Параметры подключения к общим принтерам (Point and Print) позволяют'),
('Настройка Point and Print разрешает','Настройка подключения к общим принтерам (Point and Print) разрешает'),
('предупреждения Point and Print,','предупреждения при подключении к общим принтерам (Point and Print),'),
('Ограничения Point and Print заданы','Ограничения подключения к общим принтерам (Point and Print) заданы'),
('настройки Point and Print влияют','настройки подключения к общим принтерам (Point and Print) влияют'),
('Point and Print позволяет','Подключение к общим принтерам (Point and Print) позволяет'),
('Запросы повышения прав Point and Print скрыты','Запросы повышения прав при подключении к общим принтерам (Point and Print) скрыты'),
('Point and Print Restrictions: ограничения','Политика ограничений подключения к общим принтерам (Point and Print Restrictions): ограничения'),
('Принудительное применение Package Point and Print','Принудительное применение подключения с пакетами драйверов (Package Point and Print)'),
('параметры Point and Print или установки','параметры подключения к общим принтерам (Point and Print) или установки'),
('использует вариант Point and Print без пакета драйвера','использует вариант подключения к общему принтеру (Point and Print) без пакета драйвера'),
('Включите Extended Protection for Authentication (EPA)','Включите расширенную защиту для проверки подлинности (EPA)'),
('Рассмотрите Extended Protection for Authentication (EPA)','Рассмотрите расширенную защиту для проверки подлинности (EPA)'),
('без обязательной Extended Protection for Authentication (EPA)','без обязательной расширенной защиты для проверки подлинности (EPA)'),
('включена Extended Protection for Authentication (EPA)','включена расширенная защита для проверки подлинности (EPA)'),
('без Extended Protection for Authentication (EPA)','без расширенной защиты для проверки подлинности (EPA)'),
('Включить Extended Protection for Authentication для','Включить расширенную защиту для проверки подлинности (EPA) для'),
('Проверить Extended Protection для','Проверить расширенную защиту (Extended Protection) для'),
('Selective Authentication дополнительно','Выборочная проверка подлинности (Selective Authentication) дополнительно'),
('используйте Selective Authentication (выборочную аутентификацию)','используйте выборочную проверку подлинности (Selective Authentication)'),
('применяйте Selective Authentication.','применяйте выборочную проверку подлинности (Selective Authentication).'),
('Рассмотрите Fine-Grained Password Policies для','Рассмотрите детализированные политики паролей (FGPP) для'),
('Включите Manager Approval для','Включите обязательное одобрение администратором ЦС (Manager Approval) для'),
('При установленном Block Inheritance','При включённой блокировке наследования (Block Inheritance)'),
('включает Block Inheritance для','включает блокировку наследования (Block Inheritance) для'),
('как Enforced: Block Inheritance не','как принудительные (Enforced): блокировка наследования не'),
]
STATIC={
'Summary = "Анализ сохранённых в AD данных Credential Roaming."':'Summary = "Анализ перемещаемых учётных данных, сохранённых в AD."',
'Summary = "Поиск раскрытия паролей и других секретов в Group Policy Preferences (GPP)."':'Summary = "Поиск раскрытия паролей и других секретов в предпочтениях групповой политики (GPP)."',
'SectionTitle = "Политики установки драйверов Point and Print"':'SectionTitle = "Политики установки драйверов принтеров (Point and Print)"',
'Summary = "Проверка ограничений Point and Print для установки драйверов принтеров."':'Summary = "Проверка ограничений установки драйверов при подключении к общим принтерам (Point and Print)."',
}
def sha(b): return hashlib.sha256(b).hexdigest()
def extract(s,n): return re.search(r'\bconst '+n+r'\s*=\s*(\{[^\n]+\});',s)
def walk(x,path=()):
 if isinstance(x,dict):
  for k,v in x.items(): yield from walk(v,path+(k,))
 elif isinstance(x,list):
  for i,v in enumerate(x): yield from walk(v,path+(i,))
 elif isinstance(x,str): yield path,x
def update(x,path,value):
 for k in path[:-1]: x=x[k]
 x[path[-1]]=value
def compact(j): return json.dumps(j,ensure_ascii=False,separators=(',',':')).replace('<','\\u003c').replace('\u2028','\\u2028').replace('\u2029','\\u2029')
def create_manifest(s):
 out={}
 for n in NAMES:
  m=extract(s,n); d=json.loads(m[1]); changes=[]
  for path,x in walk(d):
   v=x
   for a,b in RULES: v=v.replace(a,b)
   if v!=x:changes.append({'path':path,'old':x,'new':v})
  out[n]={'sourceSha256':sha(m[1].encode()),'changes':changes}
 return out
def patch_js(s,manifest):
 for name,meta in manifest.items():
  m=extract(s,name); assert m and sha(m[1].encode())==meta['sourceSha256'],name
  d=json.loads(m[1])
  for c in meta['changes']:
   x=d
   for k in c['path']:x=x[k]
   assert x==c['old']; update(d,c['path'],c['new'])
  s=s[:m.start(1)]+compact(d)+s[m.end(1):]
 return s
def patch_static(s):
 for a,b in STATIC.items():
  assert s.count(a)==1,a
  s=s.replace(a,b)
 return s
if __name__=='__main__':
 ap=argparse.ArgumentParser();ap.add_argument('--candidate',type=Path,required=True);ap.add_argument('--manifest',type=Path,required=True);a=ap.parse_args();m=json.loads(a.manifest.read_text(encoding='utf-8-sig'))
 if a.candidate.is_file():
  raw=a.candidate.read_bytes(); s=raw.decode('utf-8-sig'); out=patch_static(patch_js(s,m));a.candidate.write_bytes((b'\xef\xbb\xbf' if raw.startswith(b'\xef\xbb\xbf') else b'')+out.encode())
 else:
  p=a.candidate/'src/modules/Reporting/templates/report-scripts.js';raw=p.read_bytes(); out=patch_js(raw.decode('utf-8-sig'),m)
  plans={p:out}
  for old,new in STATIC.items():
   hits=[]
   for f in (a.candidate/'src').rglob('*.ps1'):
    t=plans.get(f,f.read_bytes().decode('utf-8-sig'))
    if old in t:hits.append((f,t))
   assert len(hits)==1 and hits[0][1].count(old)==1,old
   f,t=hits[0];plans[f]=t.replace(old,new)
  for f,t in plans.items():f.write_bytes((b'\xef\xbb\xbf' if f.read_bytes().startswith(b'\xef\xbb\xbf') else b'')+t.encode())
