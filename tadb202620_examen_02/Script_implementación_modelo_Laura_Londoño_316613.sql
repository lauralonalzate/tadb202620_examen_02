-- =====================================================================
-- Examen 02 – Tópicos Avanzados de Bases de Datos (periodo 202620)
-- Script de implementación del modelo de datos (Etapa 2)
-- Estudiante: Laura Londoño – ID SIGAA 316613
-- Motor: PostgreSQL 18.6 (Neon)
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. Esquema
-- ---------------------------------------------------------------------
CREATE SCHEMA brechas_seguridad AUTHORIZATION CURRENT_USER;

SET search_path TO brechas_seguridad;


-- ---------------------------------------------------------------------
-- 2. Secuencias (una por cada tabla con id propio)
-- ---------------------------------------------------------------------
CREATE SEQUENCE seq_organizaciones;
CREATE SEQUENCE seq_brechas;
CREATE SEQUENCE seq_usuarios;
CREATE SEQUENCE seq_tipos_dato;


-- ---------------------------------------------------------------------
-- 3. Tablas y restricciones
-- ---------------------------------------------------------------------
CREATE TABLE organizaciones (
    id                INTEGER      NOT NULL DEFAULT nextval('seq_organizaciones'),
    nombre            VARCHAR(150) NOT NULL,
    sector            VARCHAR(100) NOT NULL,
    pais              VARCHAR(80)  NOT NULL,
    tamano_empleados  VARCHAR(50)  NOT NULL,
    CONSTRAINT pk_organizaciones PRIMARY KEY (id),
    CONSTRAINT uq_organizaciones_nombre UNIQUE (nombre)
);

CREATE TABLE tipos_dato (
    id                      INTEGER      NOT NULL DEFAULT nextval('seq_tipos_dato'),
    nombre                  VARCHAR(100) NOT NULL,
    categoria_sensibilidad  VARCHAR(20)  NOT NULL,
    CONSTRAINT pk_tipos_dato PRIMARY KEY (id),
    CONSTRAINT uq_tipos_dato_nombre UNIQUE (nombre),
    CONSTRAINT ck_tipos_dato_categoria
        CHECK (categoria_sensibilidad IN ('Baja', 'Media', 'Alta', 'Critica'))
);

CREATE TABLE brechas (
    id                   INTEGER       NOT NULL DEFAULT nextval('seq_brechas'),
    codigo               VARCHAR(50)   NOT NULL,
    id_organizacion      INTEGER       NOT NULL,
    fecha_ocurrencia     DATE          NOT NULL,
    fecha_deteccion      DATE          NOT NULL,
    vector_ataque        VARCHAR(100)  NOT NULL,
    severidad            VARCHAR(20)   NOT NULL,
    registros_afectados  BIGINT        NOT NULL,
    costo_estimado       NUMERIC(15,2) NOT NULL,
    CONSTRAINT pk_brechas PRIMARY KEY (id),
    CONSTRAINT uq_brechas_codigo UNIQUE (codigo),
    CONSTRAINT fk_brechas_organizacion FOREIGN KEY (id_organizacion)
        REFERENCES organizaciones (id),
    CONSTRAINT ck_brechas_severidad
        CHECK (severidad IN ('Baja', 'Media', 'Alta', 'Critica'))
);

CREATE TABLE usuarios (
    id               INTEGER      NOT NULL DEFAULT nextval('seq_usuarios'),
    codigo           VARCHAR(50)  NOT NULL,
    id_organizacion  INTEGER      NOT NULL,
    pseudonimo       VARCHAR(100) NOT NULL,
    email_hash       VARCHAR(128) NOT NULL,
    pais_residencia  VARCHAR(80)  NOT NULL,
    fecha_registro   DATE         NOT NULL,
    CONSTRAINT pk_usuarios PRIMARY KEY (id),
    CONSTRAINT uq_usuarios_codigo UNIQUE (codigo),
    CONSTRAINT fk_usuarios_organizacion FOREIGN KEY (id_organizacion)
        REFERENCES organizaciones (id)
);

CREATE TABLE exposiciones (
    id_usuario          INTEGER NOT NULL,
    id_brecha           INTEGER NOT NULL,
    id_tipo_dato        INTEGER NOT NULL,
    fecha_notificacion  DATE    NOT NULL,
    CONSTRAINT pk_exposiciones PRIMARY KEY (id_usuario, id_brecha, id_tipo_dato),
    CONSTRAINT fk_exposiciones_usuario FOREIGN KEY (id_usuario)
        REFERENCES usuarios (id),
    CONSTRAINT fk_exposiciones_brecha FOREIGN KEY (id_brecha)
        REFERENCES brechas (id),
    CONSTRAINT fk_exposiciones_tipo_dato FOREIGN KEY (id_tipo_dato)
        REFERENCES tipos_dato (id)
);

-- Las secuencias quedan ligadas a su columna: si se borra la tabla,
-- se borra su secuencia.
ALTER SEQUENCE seq_organizaciones OWNED BY organizaciones.id;
ALTER SEQUENCE seq_brechas        OWNED BY brechas.id;
ALTER SEQUENCE seq_usuarios       OWNED BY usuarios.id;
ALTER SEQUENCE seq_tipos_dato     OWNED BY tipos_dato.id;


-- ---------------------------------------------------------------------
-- 4. Índices sobre las llaves foráneas
-- ---------------------------------------------------------------------
-- PostgreSQL no crea índices para las FK automáticamente.
CREATE INDEX idx_brechas_id_organizacion      ON brechas (id_organizacion);
CREATE INDEX idx_usuarios_id_organizacion     ON usuarios (id_organizacion);
CREATE INDEX idx_exposiciones_id_brecha       ON exposiciones (id_brecha);
CREATE INDEX idx_exposiciones_id_tipo_dato    ON exposiciones (id_tipo_dato);
-- exposiciones.id_usuario no lleva índice aparte: es la primera columna
-- de pk_exposiciones, así que el índice de la PK ya lo cubre.


-- ---------------------------------------------------------------------
-- 5. Tabla staging (la sábana tal como viene en los CSV)
-- ---------------------------------------------------------------------
-- Los nombres de columna son idénticos a los encabezados del CSV para
-- que DBeaver los mapee automáticamente al importar.
CREATE TABLE staging_sabana (
    nombre_organizacion            TEXT,
    sector_organizacion            TEXT,
    pais_organizacion              TEXT,
    tamano_empleados_organizacion  TEXT,
    codigo_brecha                  TEXT,
    fecha_ocurrencia               TEXT,
    fecha_deteccion                TEXT,
    vector_ataque                  TEXT,
    severidad_incidente            TEXT,
    registros_afectados_total      TEXT,
    costo_estimado_total           TEXT,
    codigo_usuario                 TEXT,
    pseudonimo_usuario             TEXT,
    email_hash_usuario             TEXT,
    pais_residencia_usuario        TEXT,
    fecha_registro_usuario         TEXT,
    tipo_dato_expuesto             TEXT,
    categoria_sensibilidad_dato    TEXT,
    fecha_notificacion_usuario     TEXT
);

-- Verificar que las columnas de la staging coinciden con los encabezados
-- del CSV antes de importar.
SELECT column_name
FROM information_schema.columns
WHERE table_schema = 'brechas_seguridad'
  AND table_name = 'staging_sabana'
ORDER BY ordinal_position;

-- >>> PAUSA: importar aquí los 4 CSV (sabana_brechas_seguridad_lote_#.csv)
--     a staging_sabana con el asistente de importación de DBeaver.
--     Después continuar con la sección 6.

--Comprobar que si se importaron bien los datos
--Se puede ir ejecutando después de cada csv, debe ir incrementando de 10k en 10k hasta 40k
SELECT count(*) FROM brechas_seguridad.staging_sabana;

-- ---------------------------------------------------------------------
-- 6. Procedimiento: carga de la staging a las 5 tablas
-- ---------------------------------------------------------------------
-- Se puede ejecutar más de una vez: ON CONFLICT evita duplicados.
-- SET search_path hace que encuentre las tablas desde cualquier sesión.
CREATE PROCEDURE sp_cargar_modelo()
LANGUAGE plpgsql
SET search_path = brechas_seguridad
AS $$
BEGIN
    INSERT INTO organizaciones (nombre, sector, pais, tamano_empleados)
    SELECT DISTINCT nombre_organizacion, sector_organizacion,
           pais_organizacion, tamano_empleados_organizacion
    FROM staging_sabana
    ON CONFLICT (nombre) DO NOTHING;

    INSERT INTO tipos_dato (nombre, categoria_sensibilidad)
    SELECT DISTINCT tipo_dato_expuesto, categoria_sensibilidad_dato
    FROM staging_sabana
    ON CONFLICT (nombre) DO NOTHING;

    INSERT INTO brechas (codigo, id_organizacion, fecha_ocurrencia,
                         fecha_deteccion, vector_ataque, severidad,
                         registros_afectados, costo_estimado)
    SELECT DISTINCT s.codigo_brecha, o.id,
           s.fecha_ocurrencia::DATE, s.fecha_deteccion::DATE,
           s.vector_ataque, s.severidad_incidente,
           s.registros_afectados_total::BIGINT,
           s.costo_estimado_total::NUMERIC(15,2)
    FROM staging_sabana s
    JOIN organizaciones o ON o.nombre = s.nombre_organizacion
    ON CONFLICT (codigo) DO NOTHING;

    INSERT INTO usuarios (codigo, id_organizacion, pseudonimo, email_hash,
                          pais_residencia, fecha_registro)
    SELECT DISTINCT s.codigo_usuario, o.id, s.pseudonimo_usuario,
           s.email_hash_usuario, s.pais_residencia_usuario,
           s.fecha_registro_usuario::DATE
    FROM staging_sabana s
    JOIN organizaciones o ON o.nombre = s.nombre_organizacion
    ON CONFLICT (codigo) DO NOTHING;

    INSERT INTO exposiciones (id_usuario, id_brecha, id_tipo_dato,
                              fecha_notificacion)
    SELECT DISTINCT u.id, b.id, t.id, s.fecha_notificacion_usuario::DATE
    FROM staging_sabana s
    JOIN usuarios   u ON u.codigo = s.codigo_usuario
    JOIN brechas    b ON b.codigo = s.codigo_brecha
    JOIN tipos_dato t ON t.nombre = s.tipo_dato_expuesto
    ON CONFLICT (id_usuario, id_brecha, id_tipo_dato) DO NOTHING;
END;
$$;

-- ---------------------------------------------------------------------
-- 7. Vista que une las 5 tablas
-- ---------------------------------------------------------------------
CREATE VIEW v_exposiciones_detalle AS
SELECT u.codigo                  AS codigo_usuario,
       b.codigo                  AS codigo_brecha,
       o.nombre                  AS organizacion,
       b.fecha_ocurrencia,
       b.fecha_deteccion,
       b.vector_ataque,
       b.severidad,
       t.nombre                  AS tipo_dato,
       t.categoria_sensibilidad,
       e.fecha_notificacion
FROM exposiciones e
JOIN usuarios       u ON u.id = e.id_usuario
JOIN brechas        b ON b.id = e.id_brecha
JOIN organizaciones o ON o.id = b.id_organizacion
JOIN tipos_dato     t ON t.id = e.id_tipo_dato;


-- ---------------------------------------------------------------------
-- 8. Función: número de filas por tabla
-- ---------------------------------------------------------------------
CREATE FUNCTION fn_conteo_tablas()
RETURNS TABLE (tabla TEXT, filas BIGINT)
LANGUAGE sql
STABLE
AS $$
    SELECT 'organizaciones', COUNT(*) FROM brechas_seguridad.organizaciones
    UNION ALL
    SELECT 'brechas',        COUNT(*) FROM brechas_seguridad.brechas
    UNION ALL
    SELECT 'usuarios',       COUNT(*) FROM brechas_seguridad.usuarios
    UNION ALL
    SELECT 'tipos_dato',     COUNT(*) FROM brechas_seguridad.tipos_dato
    UNION ALL
    SELECT 'exposiciones',   COUNT(*) FROM brechas_seguridad.exposiciones;
$$;


-- ---------------------------------------------------------------------
-- 9. Carga de los datos
-- ---------------------------------------------------------------------
-- Requiere que los 4 CSV ya estén en staging_sabana (pausa de la sección 5).
--Llamar al Proc, para poblar cada una de las tablas
CALL brechas_seguridad.sp_cargar_modelo();

-- Verificar el resultado: organizaciones 60, brechas 800, usuarios 7887,
-- tipos_dato 10, exposiciones 40000.
SELECT * FROM brechas_seguridad.fn_conteo_tablas();


-- ---------------------------------------------------------------------
-- 10. Usuario de solo lectura y privilegios mínimos
-- ---------------------------------------------------------------------
-- Reemplazar <contraseña> por una contraseña propia y larga antes de
-- ejecutar. La contraseña real no se deja en el repositorio.
CREATE ROLE lector_brechas LOGIN PASSWORD '<contraseña>';

-- Se quitan los permisos que PostgreSQL da por defecto a PUBLIC,
-- para que el lector tenga solo lo que se le concede abajo.
REVOKE ALL ON DATABASE tadb_examen02 FROM PUBLIC;
REVOKE ALL ON SCHEMA brechas_seguridad FROM PUBLIC;
REVOKE EXECUTE ON ALL ROUTINES IN SCHEMA brechas_seguridad FROM PUBLIC;

GRANT CONNECT ON DATABASE tadb_examen02 TO lector_brechas;
GRANT USAGE   ON SCHEMA brechas_seguridad TO lector_brechas;
GRANT SELECT  ON organizaciones, brechas, usuarios, tipos_dato,
                 exposiciones, v_exposiciones_detalle TO lector_brechas;
GRANT EXECUTE ON FUNCTION fn_conteo_tablas() TO lector_brechas;
-- No se le da acceso a staging_sabana ni al procedimiento de carga.

-- ---------------------------------------------------------------------
-- 11. Índices adicionales para las consultas de las Etapas 3 y 4
-- ---------------------------------------------------------------------
-- Los nombres llevan el esquema para poder ejecutar esta sección sola.
 
-- Consulta 1 (Etapa 3): brechas no lleva índice adicional. Se probó un
-- índice sobre (severidad, fecha_deteccion), pero el planificador no lo
-- usó: con solo 800 filas prefiere recorrer brechas por uq_brechas_codigo,
-- porque así obtiene las filas ya ordenadas por código, que es el orden
-- que necesita el GroupAggregate de la consulta. Un índice que no se usa
-- solo ocupa espacio y hace más lentas las escrituras, así que se quitó.
 
-- Consulta 1 (Etapa 3): cuenta usuarios distintos por brecha. Con
-- (id_brecha, id_usuario) el conteo se resuelve leyendo solo el índice.
-- Reemplaza a idx_exposiciones_id_brecha: como id_brecha es la primera
-- columna, este índice también sigue cubriendo la FK.
DROP INDEX IF EXISTS brechas_seguridad.idx_exposiciones_id_brecha;
CREATE INDEX idx_exposiciones_id_brecha_id_usuario
    ON brechas_seguridad.exposiciones (id_brecha, id_usuario);
 
-- Consulta 2 (Etapa 4) no necesita índices adicionales:
--   usuarios.codigo        -> uq_usuarios_codigo (índice del UNIQUE)
--   exposiciones.id_usuario -> pk_exposiciones (primera columna de la PK)
--   brechas, organizaciones, tipos_dato -> índices de sus PK
 
-- Actualiza las estadísticas para que el planificador conozca los datos
-- cargados y los índices nuevos (ejecutar después del CALL de carga).
ANALYZE brechas_seguridad.organizaciones;
ANALYZE brechas_seguridad.brechas;
ANALYZE brechas_seguridad.usuarios;
ANALYZE brechas_seguridad.tipos_dato;
ANALYZE brechas_seguridad.exposiciones;



