-- =====================================================================
-- Examen 02 – Tópicos Avanzados de Bases de Datos (periodo 202620)
-- Script de implementación de las consultas (Etapas 3 y 4)
-- Estudiante: Laura Londoño – ID SIGAA 316613
-- Motor: PostgreSQL 18.6 (Neon)
-- =====================================================================

-- =====================================================================
-- CONSULTA 1 (Etapa 3)
-- Brechas del último año, de severidad Alta o Critica, que expusieron
-- al menos un dato de categoría Critica, con el total de usuarios
-- distintos afectados por cada brecha (todos sus usuarios, no solo los
-- del dato crítico; por eso la condición del dato crítico va en EXISTS).
-- Índices que usa según el plan: idx_exposiciones_id_brecha_id_usuario
-- (EXISTS y conteo con Index Only Scan), uq_brechas_codigo y
-- pk_organizaciones. Todos se crean en el script del modelo.
-- =====================================================================
 
-- 1.a Resultado
SELECT o.nombre                     AS organizacion,
       b.codigo                     AS codigo_brecha,
       b.fecha_deteccion,
       b.vector_ataque,
       COUNT(DISTINCT e.id_usuario) AS usuarios_afectados
FROM brechas_seguridad.brechas b
JOIN brechas_seguridad.organizaciones o ON o.id = b.id_organizacion
JOIN brechas_seguridad.exposiciones   e ON e.id_brecha = b.id
WHERE b.severidad IN ('Alta', 'Critica')
  AND b.fecha_deteccion >= (CURRENT_DATE - INTERVAL '1 year')::DATE
  AND EXISTS (
        SELECT 1
        FROM brechas_seguridad.exposiciones e2
        JOIN brechas_seguridad.tipos_dato   t ON t.id = e2.id_tipo_dato
        WHERE e2.id_brecha = b.id
          AND t.categoria_sensibilidad = 'Critica'
      )
GROUP BY o.nombre, b.codigo, b.fecha_deteccion, b.vector_ataque
ORDER BY usuarios_afectados DESC, b.codigo;
 
-- 1.b Plan de ejecución
EXPLAIN (ANALYZE)
SELECT o.nombre                     AS organizacion,
       b.codigo                     AS codigo_brecha,
       b.fecha_deteccion,
       b.vector_ataque,
       COUNT(DISTINCT e.id_usuario) AS usuarios_afectados
FROM brechas_seguridad.brechas b
JOIN brechas_seguridad.organizaciones o ON o.id = b.id_organizacion
JOIN brechas_seguridad.exposiciones   e ON e.id_brecha = b.id
WHERE b.severidad IN ('Alta', 'Critica')
  AND b.fecha_deteccion >= (CURRENT_DATE - INTERVAL '1 year')::DATE
  AND EXISTS (
        SELECT 1
        FROM brechas_seguridad.exposiciones e2
        JOIN brechas_seguridad.tipos_dato   t ON t.id = e2.id_tipo_dato
        WHERE e2.id_brecha = b.id
          AND t.categoria_sensibilidad = 'Critica'
      )
GROUP BY o.nombre, b.codigo, b.fecha_deteccion, b.vector_ataque
ORDER BY usuarios_afectados DESC, b.codigo;
 
 
-- =====================================================================
-- CONSULTA 2 (Etapa 4)
-- Historial de exposición de un usuario (derecho de acceso): brechas en
-- las que se vio afectado, tipo de dato expuesto, su categoría, la
-- organización responsable de la brecha y la fecha de notificación,
-- en orden cronológico de notificación.
-- La organización responsable es la de la brecha (b.id_organizacion),
-- no la organización a la que está asociado el usuario.
-- Índices que usa según el plan: uq_usuarios_codigo, pk_exposiciones,
-- pk_brechas, pk_organizaciones y pk_tipos_dato. Todos se crean en el
-- script del modelo.
-- =====================================================================
 
-- 2.a Resultado
SELECT b.codigo                  AS codigo_brecha,
       t.nombre                  AS tipo_dato,
       t.categoria_sensibilidad,
       o.nombre                  AS organizacion_responsable,
       e.fecha_notificacion
FROM brechas_seguridad.usuarios u
JOIN brechas_seguridad.exposiciones   e ON e.id_usuario = u.id
JOIN brechas_seguridad.brechas        b ON b.id = e.id_brecha
JOIN brechas_seguridad.organizaciones o ON o.id = b.id_organizacion
JOIN brechas_seguridad.tipos_dato     t ON t.id = e.id_tipo_dato
WHERE u.codigo = 'US-003386'
ORDER BY e.fecha_notificacion, b.codigo, t.nombre;
 
-- 2.b Plan de ejecución
EXPLAIN (ANALYZE)
SELECT b.codigo                  AS codigo_brecha,
       t.nombre                  AS tipo_dato,
       t.categoria_sensibilidad,
       o.nombre                  AS organizacion_responsable,
       e.fecha_notificacion
FROM brechas_seguridad.usuarios u
JOIN brechas_seguridad.exposiciones   e ON e.id_usuario = u.id
JOIN brechas_seguridad.brechas        b ON b.id = e.id_brecha
JOIN brechas_seguridad.organizaciones o ON o.id = b.id_organizacion
JOIN brechas_seguridad.tipos_dato     t ON t.id = e.id_tipo_dato
WHERE u.codigo = 'US-003386'
ORDER BY e.fecha_notificacion, b.codigo, t.nombre;