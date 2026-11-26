# Resistência Blackout — Terminal de Operações

Sistema de mesa da campanha **Resistência Blackout**: ficha, mochila, registros,
diário, mensagens, troféus e o mural do mapa.

A página é um arquivo só (`index.html`) e fala direto com o Supabase.
Cada jogador cria a própria ficha com usuário e senha, e o sigilo é garantido
pelo banco: as travas do `blackout-schema.sql` fazem o servidor recusar a
consulta de quem não tem direito, não só esconder na tela.

- **Jogar:** https://arkdaniel123.github.io/RPG-Resistencia-Blackout/
- **Banco:** `blackout-schema.sql` (cole no SQL Editor do Supabase)

Mestre: Daniel.
