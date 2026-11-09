# NEXUS ARENA

Juego arcade multijugador de dos jugadores. Cada jugador recoge núcleos del mapa y los entrega en su base antes de que termine el tiempo.

## Funciones de esta primera versión

- Registro e inicio de sesión con correo y contraseña (Supabase Auth).
- Perfiles con experiencia, victorias, derrotas y núcleos acumulados.
- Salas privadas de 8 caracteres para invitar a otra persona.
- Movimiento y estado de la partida sincronizados con Supabase Realtime.
- Tres clases iniciales: Guardián, Corredor e Ingeniero.
- Cuatro clases bloqueadas por logros: Magnetista, Ilusionista, Saboteador y Portalero.
- Habilidad activa y definitiva por clase.
- Historial resumido y desbloqueos guardados en Supabase.

## Arquitectura

- **Vercel:** sirve la aplicación web estática desde `index.html`.
- **GitHub:** mantiene el código fuente.
- **Supabase Auth:** gestiona las cuentas.
- **Supabase Postgres:** guarda perfiles, salas, resultados y logros.
- **Supabase Realtime:** transmite movimientos y estado de sala.

## Configuración de Supabase

El juego está preparado para el proyecto Supabase configurado en `index.html`. La clave incluida es una **publishable key** para frontend. Nunca incluyas una `service_role` o una secret key en el navegador.

Para preparar una base de datos nueva, ejecuta una sola vez el contenido de `supabase/schema.sql` en el SQL Editor de Supabase. En el proyecto actual, esas tablas y funciones ya fueron creadas y comprobadas.

En Supabase Auth, habilita Email y decide si quieres exigir confirmación de correo. Si la confirmación está activa, cada usuario debe confirmar el correo antes de iniciar sesión.

## Jugar

1. Abre la web y crea una cuenta con correo, contraseña y nombre de jugador.
2. Un jugador crea una sala y comparte el código de 8 caracteres.
3. El segundo jugador inicia sesión y entra con ese código.
4. Cuando ambos estén conectados, la partida comienza.
5. Usa **WASD** o las **flechas** para moverte, **E** para la habilidad y **Espacio** para la definitiva.
6. Recoge núcleos amarillos y vuelve a tu base (azul o morada) para entregarlos.

## Nota de la versión MVP

Esta es una primera versión jugable para probar partidas privadas casuales con amigos. La autoridad del movimiento la tiene el navegador del anfitrión y el registro de resultados es una llamada autenticada; antes de usar rankings competitivos o torneos con premios, se debe trasladar la simulación y validación del marcador a lógica de servidor autoritativa y añadir protecciones anti-trampas.

## Despliegue

El sitio no requiere proceso de build: Vercel puede servir directamente el `index.html` desde la raíz del repositorio. El proyecto de Vercel debe apuntar a este repositorio y usar framework **Other** (o detección estática).
