"""Apply readable Lua sources to a separate Studio XML output. Never overwrites the main place."""
from pathlib import Path
import json, xml.etree.ElementTree as ET
root=Path(__file__).resolve().parents[1]
tree=ET.parse(root/'RIFT_PROTOCOL_WORKING.rbxlx')
for entry in json.loads((root/'scripts/source-map.json').read_text(encoding='utf-8')):
    node=tree.getroot()
    for index in entry['indices']: node=node.findall('Item')[index]
    node.find("./Properties/*[@name='Source']").text=(root/entry['file']).read_text(encoding='utf-8')
dest=root/'build/RIFT_PROTOCOL_EDITED.rbxlx'
dest.parent.mkdir(exist_ok=True)
tree.write(dest,encoding='utf-8',xml_declaration=True)
ET.parse(dest)
print('Built build/RIFT_PROTOCOL_EDITED.rbxlx; open this copy in Studio and Play-test.')
