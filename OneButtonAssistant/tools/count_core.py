from pathlib import Path
p=Path('C:/Lazy Hero/OneButtonAssistant/OneButtonAssistant_core.lua')
s=p.read_text(encoding='utf-8',errors='ignore')
print('functions:', s.count('\nfunction '))
print('ends:', s.count('\nend\n'))
print('\n--- tail ---')
for l in s.splitlines()[-120:]:
    print(l)
