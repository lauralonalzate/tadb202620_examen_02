# Examen 02 – Índices y mejoras en el desempeño de consultas

**Tópicos Avanzados de Bases de Datos · Periodo 202620**
Universidad Pontificia Bolivariana · Docente: Juan Darío Rodas M.
Dominio del problema: análisis de brechas de seguridad.

## Estudiante

| Nombre | ID SIGAA | Motor de base de datos |
|---|---|---|
| Laura Londoño | 316613 | PostgreSQL 18.6 |

Entrega individual.

## Infraestructura

- PostgreSQL 18.6 en Neon (plan gratuito, región AWS US East 2), base de datos `tadb_examen02`.
- Conexión desde DBeaver con cifrado TLS obligatorio.
- El detalle está en el documento de abastecimiento.

## Contenido del repositorio

| Archivo | Etapa | Contenido |
|---|---|---|
| [Abastecimiento_base_de_datos_Laura_Londoño_316613.pdf](Abastecimiento_base_de_datos_Laura_Londoño_316613.pdf) | 1 | Abastecimiento en Neon y conexión desde DBeaver |
| [Diagrama_relacional_Laura_Londoño_316613.png](Diagrama_relacional_Laura_Londoño_316613.png) | 2 | Diagrama relacional |
| [Script_implementación_modelo_Laura_Londoño_316613.sql](Script_implementación_modelo_Laura_Londoño_316613.sql) | 2 | Esquema, secuencias, tablas, restricciones, índices, tabla staging, procedimiento de carga, vista, función, usuario de solo lectura y privilegios |
| [Script_implementación_consultas_Laura_Londoño_316613.sql](Script_implementación_consultas_Laura_Londoño_316613.sql) | 3 y 4 | Consultas y sus planes de ejecución (`EXPLAIN (ANALYZE)`) |
| [Plan_de_ejecuciónXconsulta_Laura_Londoño_316613.docx](Plan_de_ejecuciónXconsulta_Laura_Londoño_316613.docx) | 3 y 4 | Plan de ejecución de cada consulta (árbol, filas y costo) y registros resultantes |
| [Interacción_IA_Laura_Londoño_316613.pdf](Interacción_IA_Laura_Londoño_316613.pdf) | – | Capturas de la interacción con la IA |
| `.gitignore` | – | Archivos excluidos del repositorio |

Los archivos de la sábana (`sabana_brechas_seguridad_lote_#.zip`) los entrega el docente y no se incluyen.

## Modelo de datos

Esquema `brechas_seguridad`, con 5 tablas obtenidas al normalizar la sábana de 40.000 filas:

| Tabla | Filas | Descripción |
|---|---|---|
| `organizaciones` | 60 | Organización afectada: sector, país y tamaño |
| `brechas` | 800 | Incidente: organización, fechas, vector de ataque, severidad, registros afectados y costo |
| `usuarios` | 7.887 | Usuario seudonimizado, asociado a una organización |
| `tipos_dato` | 10 | Catálogo de tipos de dato con su categoría de sensibilidad |
| `exposiciones` | 40.000 | Tabla puente usuario–brecha–tipo de dato, con la fecha de notificación |

Objetos adicionales:
- Una secuencia por tabla con id propio.
- La tabla `staging_sabana` y el procedimiento `sp_cargar_modelo()`, que cargan los datos.
- La vista `v_exposiciones_detalle`.
- La función `fn_conteo_tablas()`.
- El usuario de solo lectura `lector_brechas`.

## Decisiones de diseño

Todas las decisiones se verificaron contra las 40.000 filas de la sábana.

1. **Cinco tablas a partir de las dependencias funcionales.** Cada grupo de columnas depende únicamente de su propia clave, y las cuatro dependencias se cumplen sin ninguna excepción:
   - nombre de la organización → sector, país, tamaño
   - código de brecha → organización, fechas, vector, severidad, registros, costo
   - código de usuario → pseudónimo, hash del correo, país, fecha de registro
   - tipo de dato → categoría de sensibilidad

   Separar cada grupo en su propia tabla elimina las dependencias parciales y transitivas, así que el modelo queda en tercera forma normal. Los conteos coinciden con el enunciado: 60, 800, 7.887 y 10.

2. **Tabla puente ternaria `exposiciones`, con PK compuesta (`id_usuario`, `id_brecha`, `id_tipo_dato`).** La relación muchos a muchos involucra a las tres entidades. La fecha de notificación depende de las tres juntas: en 5.026 pares usuario–brecha la fecha cambia según el tipo de dato. Por eso esa fecha no cabe en una tabla puente de solo usuario y brecha. La tripleta nunca se repite en la sábana, así que sirve como clave primaria natural y evita duplicados sin agregar un id artificial.

3. **`usuarios` lleva una FK a `organizaciones`.** El enunciado asocia cada usuario a una organización. En los datos, cada uno de los 7.887 usuarios aparece solo en brechas de una misma organización.

4. **Claves sustitutas enteras alimentadas por secuencias, más `UNIQUE` sobre las claves naturales.**
   - En la sábana, organizaciones y tipos de dato no tienen código; brechas y usuarios sí.
   - Con un id entero en todas las tablas, las FK y los joins usan el mismo tipo compacto.
   - Las restricciones `UNIQUE` sobre el nombre o el código conservan la identidad natural de cada fila. También evitan duplicados al recargar los datos, porque el procedimiento usa `ON CONFLICT`.
   - Las secuencias son explícitas y quedan ligadas a su columna con `OWNED BY`.

5. **Sector, país y vector de ataque son columnas, no catálogos aparte.**
   - El enunciado espera un modelo de cinco tablas.
   - Ninguna de las consultas filtra por esos campos.
   - Se descartó crear tablas de catálogo, porque agregaban joins sin beneficio para las consultas pedidas.

6. **`CHECK` sobre la severidad y la categoría de sensibilidad.** Son dominios cerrados de cuatro valores y la consulta de la etapa 3 filtra por ellos. Un valor mal escrito, como "Crítica" con tilde, quedaría excluido de esa consulta sin que nadie lo notara. Los datos vienen sin tildes, y los `CHECK` usan exactamente esos valores.

7. **Tipos de datos.**
   - `DATE` para todas las fechas.
   - `NUMERIC(15,2)` para el costo, porque es dinero y necesita precisión exacta.
   - `BIGINT` para los registros afectados.
   - `tamano_empleados` es texto porque toma solo 10 valores fijos (50, 100, 250, …). Funciona como una categoría de tamaño y no se usa en operaciones aritméticas.

8. **Carga en dos pasos.** Los CSV se importan a `staging_sabana`, cuyas columnas son todas `TEXT`, así que la importación nunca falla por el tipo de un dato. Después, `sp_cargar_modelo()` convierte los tipos y reparte los datos en las cinco tablas, en orden de dependencia. Se puede ejecutar más de una vez sin generar duplicados.

9. **Privilegios mínimos.** `lector_brechas` solo tiene:
   - `CONNECT` sobre la base;
   - `USAGE` sobre el esquema;
   - `SELECT` sobre las 5 tablas y la vista;
   - `EXECUTE` sobre la función.

   No ve la staging ni puede ejecutar la carga. Además, se revocan los permisos que PostgreSQL da por defecto a `PUBLIC`.

10. **Nomenclatura.**
    - Todo en español y en snake_case. Las tablas van en plural.
    - La PK de cada tabla se llama `id` y las FK se llaman `id_<entidad>`.
    - Las restricciones y los objetos llevan prefijo: `pk_`, `fk_`, `uq_`, `ck_`, `idx_`, `seq_`, `sp_`, `fn_` y `v_`.

## Vistas e índices

**Vista `v_exposiciones_detalle`.** Une las cinco tablas en una sola fila legible: usuario, brecha, organización, tipo de dato, categoría y fecha de notificación. Sirve para responder solicitudes de derecho de acceso o hacer revisiones sin escribir los cuatro joins cada vez. Las consultas de las etapas 3 y 4 se escribieron directamente sobre las tablas, para controlar los joins y los filtros.

**Índices.** PostgreSQL no crea índices para las FK por su cuenta; por eso se crearon de forma explícita.

| Índice | Columnas | Para qué sirve |
|---|---|---|
| `idx_exposiciones_id_brecha_id_usuario` | `exposiciones (id_brecha, id_usuario)` | Etapa 3: resuelve el `EXISTS` por brecha y cuenta los usuarios distintos leyendo solo el índice (Index Only Scan). También cubre la FK `id_brecha`. |
| `pk_exposiciones` | `exposiciones (id_usuario, id_brecha, id_tipo_dato)` | Etapa 4: encuentra las exposiciones del usuario (Bitmap Index Scan). Como `id_usuario` es la primera columna, también cubre esa FK. |
| `uq_usuarios_codigo` | `usuarios (codigo)` | Etapa 4: ubica al usuario por su código leyendo una sola fila. |
| `uq_brechas_codigo` | `brechas (codigo)` | Etapa 3: el planificador lo usa para leer las brechas ya ordenadas por código, que es el orden que necesita la agrupación. |
| `idx_brechas_id_organizacion`, `idx_usuarios_id_organizacion`, `idx_exposiciones_id_tipo_dato` | Columnas FK | Soporte de los joins y de la integridad referencial. |

- Se descartó un índice sobre `brechas (severidad, fecha_deteccion)`. Con solo 800 filas, el planificador no lo usó.
- Después de la carga se ejecuta `ANALYZE` para que el planificador tenga estadísticas actualizadas.

## Orden de ejecución

1. Conectarse a `tadb_examen02` con el rol dueño de la base.
2. Ejecutar el script del modelo hasta la sección 5: esquema, secuencias, tablas, índices de las FK y staging.
3. Importar los 4 CSV a `staging_sabana` con el asistente de importación de DBeaver. El script marca esta pausa.
4. Reemplazar `<contraseña>` en la sección 10 y ejecutar el resto del script del modelo (secciones 6 a 11): procedimiento, vista, función, carga de datos, usuario y privilegios, e índices de desempeño.
5. Ejecutar el script de consultas.

## Consultas

| Consulta | Etapa | Filas | Costo total | Tiempo de ejecución |
|---|---|---|---|---|
| Brechas críticas del último año con mayor impacto en usuarios | 3 | 101 | 1257,26 | 86,5 ms |
| Historial de exposición del usuario `US-003386` | 4 | 20 | 33,64 | 0,22 ms |

- La consulta de la etapa 3 filtra con `CURRENT_DATE`, así que su resultado depende del día en que se ejecute. Los valores de la tabla son del 13 de octubre de 2026.
- Los índices que usa cada consulta están en la sección [Vistas e índices](#vistas-e-índices).

## Uso de inteligencia artificial
La única herramienta que usé fué el Claude de una amiga, se puede ver la interacción en el archivo 'Interacción_IA_Laura_Londoño_316613.pdf'# tadb202620_examen_02
