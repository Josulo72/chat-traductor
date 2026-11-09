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
- **Funcionalidad v2 actual**: mensajes de texto, fotos y vídeos (hasta 25 MB por archivo). Añadidas notas de voz, llamadas de voz y videollamadas WebRTC, y foto de perfil editable del administrador. Reacciones y notificaciones push con la web cerrada siguen pendientes.
- **Medios privados**: bucket `chat-v2-media` con RLS por conversación. Permite JPEG, PNG, WebP, GIF, HEIC, HEIF, MP4, MOV y WebM según soporte del dispositivo. Los medios se recuperan mediante descargas autenticadas y no se publica una URL pública permanente.
- **Interfaz**: botón + en el administrador para preparar un chat, y botón + junto al campo de texto para adjuntar fotos o vídeos en ambos extremos.

## Base de datos
`migrations/chat_v2_private_es_pt.sql` crea las nuevas tablas, funciones de acceso y reglas RLS. No elimina datos antiguos.

## Código
La v1 original es una compilación React/Vite sin fuentes. La v2 se ofrece como HTML/JavaScript editable en `index.html`. La función de traducción está en `supabase/functions/chat-translate-v2/index.ts`.

## Llamadas WebRTC
Llamadas 1:1 cuando los dos participantes tienen la web abierta. Señalización RLS por sala en `chat_v2_calls` y `chat_v2_ice_candidates`. Se emplea STUN público; sin servidor TURN la conexión no está garantizada entre redes móviles/NAT estrictas. No se ha completado prueba de extremo a extremo en dos dispositivos, y no hay avisos de llamada con la aplicación cerrada.

## Mensajes de voz y avatar
Audio grabado con `MediaRecorder` y guardado en bucket privado; los formatos disponibles dependen del navegador (especialmente Safari/iOS). Foto del administrador editable mediante «Mi foto», privada en Storage, visible únicamente a participantes autenticados. Ninguno de estos flujos se ha validado todavía con dos dispositivos físicos.
