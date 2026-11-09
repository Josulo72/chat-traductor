# chat-traductor

Chat privado con traducción automática **español ↔ portugués de Brasil (pt-BR)**.

- **Stack**: frontend estático HTML/JS, Supabase (Auth anónima, PostgreSQL con RLS, Realtime), DeepL (Edge Function).
- **Web**: https://josulo72.github.io/chat-traductor/
- **Acceso**: cada visitante escribe su nombre y crea una conversación individual. El nombre es visible al administrador, pero no a otros visitantes.
- **Privacidad**: la identidad de cada conversación se obtiene de Auth, no del nombre. RLS de Supabase restringe habitaciones y mensajes por usuario, incluso en consultas directas.
- **Administrador**: https://josulo72.github.io/chat-traductor/?admin para reclamar una sola vez el acceso mediante una clave inicial privada. La contraseña no se guarda en GitHub. Una vez reclamado, la sesión queda en ese navegador.
- **Administración**: lista de chats, apertura y cierre de acceso por conversación, sin contadores públicos.
- **Traducción**: función Edge `chat-translate-v2`, requiere el secreto `DEEPL_API_KEY` ya disponible en Supabase.
- **Persistencia**: la sesión anónima se guarda en el navegador; si una persona borra los datos locales no podrá recuperar automáticamente la misma conversación.
- **Restricción**: quien conozca la URL pública puede crear una conversación nueva; un nombre no permite excluir definitivamente a una persona concreta.
- **Funcionalidad v2 actual**: mensajes de texto. Las funciones multimedia de la compilación anterior no están migradas.

## Base de datos
`migrations/chat_v2_private_es_pt.sql` crea las nuevas tablas, funciones de acceso y reglas RLS. No elimina datos antiguos.

## Código
La v1 original es una compilación React/Vite sin fuentes. La v2 se ofrece como HTML/JavaScript editable en `index.html`. La función de traducción está en `supabase/functions/chat-translate-v2/index.ts`.
