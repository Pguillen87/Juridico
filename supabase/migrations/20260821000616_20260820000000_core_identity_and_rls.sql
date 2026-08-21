-- Migration: 20260820000000_core_identity_and_rls
-- Descrição: Criação do núcleo de identidade, tabelas office e user_profile, invariantes e RLS.

-- 1. Enums
CREATE TYPE public.user_role AS ENUM ('lawyer', 'operator', 'reviewer', 'auditor');

-- 2. Tabela Office
CREATE TABLE public.office (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name TEXT NOT NULL,
    is_active BOOLEAN NOT NULL DEFAULT true,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Habilitar RLS na tabela office
ALTER TABLE public.office ENABLE ROW LEVEL SECURITY;
-- Apenas leitura e update limitados no office para authenticated nesta fase
GRANT SELECT, UPDATE ON public.office TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.office TO service_role;

-- 3. Tabela User Profile
CREATE TABLE public.user_profile (
    id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    office_id UUID NOT NULL REFERENCES public.office(id) ON DELETE RESTRICT,
    name TEXT NOT NULL,
    role public.user_role NOT NULL,
    is_owner BOOLEAN NOT NULL DEFAULT false,
    is_active BOOLEAN NOT NULL DEFAULT true,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Índices
CREATE INDEX idx_user_profile_office_id ON public.user_profile(office_id);
CREATE INDEX idx_user_profile_role ON public.user_profile(role);
CREATE INDEX idx_user_profile_is_owner ON public.user_profile(is_owner);
CREATE INDEX idx_user_profile_is_active ON public.user_profile(is_active);

-- Habilitar RLS na tabela user_profile
ALTER TABLE public.user_profile ENABLE ROW LEVEL SECURITY;
-- Apenas leitura e update limitados no user_profile para authenticated nesta fase
GRANT SELECT, UPDATE ON public.user_profile TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.user_profile TO service_role;

-- 4. Função para obter o perfil do usuário logado de forma segura (Security Definer para ler apenas o próprio perfil caso necessário, mas RLS já cobre a própria leitura)
-- Criamos um helper STABLE para uso nas policies
CREATE OR REPLACE FUNCTION public.get_auth_user_profile()
RETURNS SETOF public.user_profile
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
    SELECT up.* FROM public.user_profile up
    JOIN public.office o ON up.office_id = o.id
    WHERE up.id = auth.uid() AND up.is_active = true AND o.is_active = true;
$$;

-- 5. Policies para public.office
-- Um usuário só pode ler o office ao qual pertence
CREATE POLICY "Users can view their own office"
ON public.office
FOR SELECT
TO authenticated
USING (
    id = (SELECT office_id FROM public.get_auth_user_profile() LIMIT 1)
);

-- Apenas owner pode atualizar o nome do office (is_active não pode ser mudado por ele mesmo para evitar lockout do tenant, ou requer cuidado extra, mas para o MVP deixamos update restrito)
CREATE POLICY "Owners can update their office"
ON public.office
FOR UPDATE
TO authenticated
USING (
    id = (SELECT office_id FROM public.get_auth_user_profile() WHERE is_owner = true LIMIT 1)
)
WITH CHECK (
    id = (SELECT office_id FROM public.get_auth_user_profile() WHERE is_owner = true LIMIT 1)
);

-- 6. Policies para public.user_profile
-- Usuários ativos em offices ativos podem ver seu próprio perfil
CREATE POLICY "Users can view their own profile"
ON public.user_profile
FOR SELECT
TO authenticated
USING (
    id = auth.uid() AND is_active = true AND (SELECT is_active FROM public.office WHERE id = office_id) = true
);

-- Owners podem ver todos os perfis do seu office
CREATE POLICY "Owners can view all profiles in their office"
ON public.user_profile
FOR SELECT
TO authenticated
USING (
    office_id = (SELECT office_id FROM public.get_auth_user_profile() WHERE is_owner = true LIMIT 1)
);

-- Owners podem atualizar perfis do seu office
CREATE POLICY "Owners can update profiles in their office"
ON public.user_profile
FOR UPDATE
TO authenticated
USING (
    office_id = (SELECT office_id FROM public.get_auth_user_profile() WHERE is_owner = true LIMIT 1)
)
WITH CHECK (
    office_id = (SELECT office_id FROM public.get_auth_user_profile() WHERE is_owner = true LIMIT 1)
);

-- 7. Invariantes Transacionais via Triggers

-- A. Proteção contra autoelevação e mudança de próprio role
CREATE OR REPLACE FUNCTION public.prevent_self_elevation()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
BEGIN
    IF auth.uid() = NEW.id THEN
        IF OLD.role IS DISTINCT FROM NEW.role THEN
            RAISE EXCEPTION 'Users cannot change their own role';
        END IF;
        IF OLD.is_owner IS DISTINCT FROM NEW.is_owner THEN
            RAISE EXCEPTION 'Users cannot change their own is_owner status';
        END IF;
        IF OLD.office_id IS DISTINCT FROM NEW.office_id THEN
            RAISE EXCEPTION 'Users cannot change their own office_id';
        END IF;
    END IF;
    RETURN NEW;
END;
$$;

CREATE TRIGGER tr_prevent_self_elevation
BEFORE UPDATE ON public.user_profile
FOR EACH ROW
EXECUTE FUNCTION public.prevent_self_elevation();

-- B. Proteção do último owner ativo
CREATE OR REPLACE FUNCTION public.protect_last_active_owner()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
    active_owners_count INTEGER;
BEGIN
    -- Se está removendo o status de owner, inativando, ou deletando (no caso de DELETE)
    IF (TG_OP = 'UPDATE' AND OLD.is_owner = true AND OLD.is_active = true AND (NEW.is_owner = false OR NEW.is_active = false))
       OR (TG_OP = 'DELETE' AND OLD.is_owner = true AND OLD.is_active = true) THEN
        
        -- Obter lock exclusivo sobre a linha do office para serializar transações concorrentes
        PERFORM 1
        FROM public.office
        WHERE id = OLD.office_id
        FOR UPDATE;
        
        -- Contar quantos owners ativos existem neste office, já sob lock
        SELECT count(*) INTO active_owners_count
        FROM public.user_profile
        WHERE office_id = OLD.office_id
          AND is_owner = true
          AND is_active = true
          AND id != OLD.id;
        
        IF active_owners_count = 0 THEN
            RAISE EXCEPTION 'Cannot remove or deactivate the last active owner of an office';
        END IF;
    END IF;
    
    IF TG_OP = 'DELETE' THEN
        RETURN OLD;
    END IF;
    RETURN NEW;
END;
$$;

CREATE TRIGGER tr_protect_last_active_owner_update
BEFORE UPDATE ON public.user_profile
FOR EACH ROW
EXECUTE FUNCTION public.protect_last_active_owner();

CREATE TRIGGER tr_protect_last_active_owner_delete
BEFORE DELETE ON public.user_profile
FOR EACH ROW
EXECUTE FUNCTION public.protect_last_active_owner();


-- 8. Restrição de privilégios de execução para funções SECURITY DEFINER
REVOKE EXECUTE ON FUNCTION public.get_auth_user_profile() FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.get_auth_user_profile() FROM anon;
GRANT EXECUTE ON FUNCTION public.get_auth_user_profile() TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_auth_user_profile() TO service_role;

REVOKE EXECUTE ON FUNCTION public.prevent_self_elevation() FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.prevent_self_elevation() FROM anon;
REVOKE EXECUTE ON FUNCTION public.prevent_self_elevation() FROM authenticated;
GRANT EXECUTE ON FUNCTION public.prevent_self_elevation() TO service_role;

REVOKE EXECUTE ON FUNCTION public.protect_last_active_owner() FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.protect_last_active_owner() FROM anon;
REVOKE EXECUTE ON FUNCTION public.protect_last_active_owner() FROM authenticated;
GRANT EXECUTE ON FUNCTION public.protect_last_active_owner() TO service_role;
