-- 04_seed_data.sql — Seed roles and a default admin user (idempotent)

-- ── Roles ─────────────────────────────────────────────────────────────────────
INSERT INTO roles (name) VALUES
    ('ROLE_USER'),
    ('ROLE_MODERATOR'),
    ('ROLE_ADMIN')
ON CONFLICT (name) DO NOTHING;

-- ── Default admin user ────────────────────────────────────────────────────────
-- Password: Admin@1234  (BCrypt rounds=12)
INSERT INTO users (id, username, email, password, enabled, first_name, last_name, created_by)
VALUES (
    gen_random_uuid(),
    'admin',
    'admin@ums.local',
    '$2a$12$T1Q1F4PnpFKVv/BoJuVxK.WF8Tc5e8p7CX.5pE3N4RJVZ6nFkHbDa',
    TRUE,
    'System',
    'Admin',
    'system'
)
ON CONFLICT (username) DO NOTHING;

-- ── Assign ADMIN role ─────────────────────────────────────────────────────────
INSERT INTO user_roles (user_id, role_id)
SELECT u.id, r.id
FROM   users u
JOIN   roles r ON r.name = 'ROLE_ADMIN'
WHERE  u.username = 'admin'
ON CONFLICT DO NOTHING;

-- ── Sample users (dev / test only) ────────────────────────────────────────────
INSERT INTO users (id, username, email, password, enabled, first_name, last_name, created_by)
VALUES
    (gen_random_uuid(), 'moderator', 'moderator@ums.local',
     '$2a$12$T1Q1F4PnpFKVv/BoJuVxK.WF8Tc5e8p7CX.5pE3N4RJVZ6nFkHbDa',
     TRUE, 'Mod', 'User', 'system'),
    (gen_random_uuid(), 'john_doe',  'john@example.com',
     '$2a$12$T1Q1F4PnpFKVv/BoJuVxK.WF8Tc5e8p7CX.5pE3N4RJVZ6nFkHbDa',
     TRUE, 'John', 'Doe', 'system')
ON CONFLICT (username) DO NOTHING;

INSERT INTO user_roles (user_id, role_id)
SELECT u.id, r.id FROM users u JOIN roles r ON r.name = 'ROLE_MODERATOR' WHERE u.username = 'moderator'
ON CONFLICT DO NOTHING;

INSERT INTO user_roles (user_id, role_id)
SELECT u.id, r.id FROM users u JOIN roles r ON r.name = 'ROLE_USER' WHERE u.username = 'john_doe'
ON CONFLICT DO NOTHING;
