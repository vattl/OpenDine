# -*- coding: utf-8 -*-
import io, re
s = io.open(r'G:\Mini Program\my_project_server\server\docs\openapi.yaml', encoding='utf-8').read()
for kw in ['selectedSpicy', 'selected_spicy', 'production_status', 'item_status', 'kds_item_status', 'kds_status_text', 'specification', 'goods_list', 'goodsList', 'spec_name', 'flavor_name', 'spicy']:
    idxs = [m.start() for m in re.finditer(re.escape(kw), s)]
    print(kw, len(idxs), idxs[:6])
