-- Demonstração das funções de limpeza e padronização do schema.
-- Dado de entrada sujo (como chega do formulário, da planilha antiga ou do WhatsApp)
-- → dado canônico que o banco guarda.
select entrada, funcao, saida
  from (values
    ('(11) 98888-7777', 'normalize_phone',   normalize_phone('(11) 98888-7777')),
    ('11988887777',     'normalize_phone',   normalize_phone('11988887777')),
    ('+55 11 98888-7777','normalize_phone',  normalize_phone('+55 11 98888-7777')),
    ('R$ 89,90',        'parse_price_cents', parse_price_cents('R$ 89,90')::text),
    ('1.299,00',        'parse_price_cents', parse_price_cents('1.299,00')::text),
    ('89.90',           'parse_price_cents', parse_price_cents('89.90')::text),
    ('abc',             'parse_price_cents', coalesce(parse_price_cents('abc')::text, 'NULL')),
    ('Calça Alfaiataria Básica', 'slugify',  slugify('Calça Alfaiataria Básica'))
  ) t(entrada, funcao, saida);
