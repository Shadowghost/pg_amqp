-- Test: Function signatures and basic validation
-- Tests that all AMQP functions exist with correct signatures

-- Verify publish function exists
SELECT proname, pronargs, prorettype::regtype
FROM pg_proc
WHERE proname = 'publish' AND pronamespace = 'amqp'::regnamespace;

-- Verify autonomous_publish function exists
SELECT proname, pronargs, prorettype::regtype
FROM pg_proc
WHERE proname = 'autonomous_publish' AND pronamespace = 'amqp'::regnamespace;

-- Verify exchange_declare function exists
SELECT proname, pronargs, prorettype::regtype
FROM pg_proc
WHERE proname = 'exchange_declare' AND pronamespace = 'amqp'::regnamespace;

-- Verify disconnect function exists
SELECT proname, pronargs, prorettype::regtype
FROM pg_proc
WHERE proname = 'disconnect' AND pronamespace = 'amqp'::regnamespace;

-- Test function argument types for publish
SELECT p.proname,
       array_agg(t.typname ORDER BY a.argnum) as arg_types
FROM pg_proc p
CROSS JOIN LATERAL unnest(p.proargtypes) WITH ORDINALITY AS a(argtype, argnum)
JOIN pg_type t ON t.oid = a.argtype
WHERE p.proname = 'publish' AND p.pronamespace = 'amqp'::regnamespace
GROUP BY p.proname;

-- Test function argument types for autonomous_publish
SELECT p.proname,
       array_agg(t.typname ORDER BY a.argnum) as arg_types
FROM pg_proc p
CROSS JOIN LATERAL unnest(p.proargtypes) WITH ORDINALITY AS a(argtype, argnum)
JOIN pg_type t ON t.oid = a.argtype
WHERE p.proname = 'autonomous_publish' AND p.pronamespace = 'amqp'::regnamespace
GROUP BY p.proname;

-- Test function argument types for exchange_declare
SELECT p.proname,
       array_agg(t.typname ORDER BY a.argnum) as arg_types
FROM pg_proc p
CROSS JOIN LATERAL unnest(p.proargtypes) WITH ORDINALITY AS a(argtype, argnum)
JOIN pg_type t ON t.oid = a.argtype
WHERE p.proname = 'exchange_declare' AND p.pronamespace = 'amqp'::regnamespace
GROUP BY p.proname;

-- Verify function comments exist
SELECT p.proname, d.description IS NOT NULL as has_comment
FROM pg_proc p
LEFT JOIN pg_description d ON d.objoid = p.oid
WHERE p.pronamespace = 'amqp'::regnamespace
ORDER BY p.proname;
