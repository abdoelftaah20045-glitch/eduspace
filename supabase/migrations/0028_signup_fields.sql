-- Signup now passes optional profile fields in the auth metadata. Idempotent.
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer set search_path = public
as $$
declare
  m jsonb := coalesce(new.raw_user_meta_data, '{}'::jsonb);
begin
  insert into public.profiles (id, full_name, email, locale, phone, country,
                               governorate, institution, birth_date)
  values (
    new.id,
    coalesce(m ->> 'full_name', ''),
    coalesce(new.email, ''),
    coalesce(m ->> 'locale', 'ar'),
    nullif(m ->> 'phone', ''),
    nullif(m ->> 'country', ''),
    nullif(m ->> 'governorate', ''),
    nullif(m ->> 'institution', ''),
    case when (m ->> 'birth_date') ~ '^\d{4}-\d{2}-\d{2}$'
         then (m ->> 'birth_date')::date else null end
  )
  on conflict (id) do nothing;
  return new;
end;
$$;
