# Castelle Express CEO — sistema de agendamento

Arquivos:
- `index.html`: site público de agendamento.
- `admin.html`: painel de agenda demonstrativo, com busca, filtros, edição, status e exportação CSV.
- `supabase_schema.sql`: estrutura pronta para conectar a um projeto Supabase.

## Para produção
1. Aplicar `supabase_schema.sql` ao projeto Supabase.
2. Criar uma conta administrativa no Supabase Auth.
3. Criar uma tabela/controle de administradores e proteger o painel com RLS/Auth.
4. Substituir o armazenamento `localStorage` do `index.html` pelas chamadas `supabase.rpc('create_appointment', ...)`.
5. Configurar o WhatsApp real do salão.
6. Publicar o site em Vercel.

A regra de disponibilidade deve ficar no banco, não apenas no navegador, para evitar dois clientes ocuparem o mesmo horário.
