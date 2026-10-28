-- #79: additive identity mapping; no existing profile/trip/event is reassigned.
-- No auth.users FK: application profiles survive Auth lifecycle changes. Account
-- deletion is out of scope, and privileged backend credentials own this mapping.
alter table public.users
    add column auth_user_id uuid,
    add constraint users_auth_user_id_key unique (auth_user_id),
    add constraint users_auth_user_id_nonzero
        check (auth_user_id <> '00000000-0000-0000-0000-000000000000'::uuid);

comment on column public.users.auth_user_id is
    'Supabase Auth subject, linked only after server verification. NULL preserves legacy/demo ownership.';

notify pgrst, 'reload schema';
