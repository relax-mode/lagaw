-- #108: prevent clients from writing destination assets through Storage directly.
-- In hosted Supabase the managed storage.objects table exists. In disposable
-- PostgreSQL CI there is no Storage service: skip these policies in that case.
-- Bucket creation/configuration is managed through the Storage API, not direct
-- metadata-table writes; see scripts/destination_images.py.
do $$
begin
    if to_regclass('storage.objects') is null then
        raise notice 'Supabase Storage is absent; apply policies on a real Supabase project';
        return;
    end if;

    -- Restrictive policies cannot be circumvented by a broad permissive policy
    -- introduced by another feature. They leave other buckets unaffected.
    execute $policy$
        create policy lagaw_destination_images_no_client_insert
        on storage.objects as restrictive for insert
        to anon, authenticated
        with check (bucket_id <> 'destination-images')
    $policy$;
    execute $policy$
        create policy lagaw_destination_images_no_client_update
        on storage.objects as restrictive for update
        to anon, authenticated
        using (bucket_id <> 'destination-images')
        with check (bucket_id <> 'destination-images')
    $policy$;
    execute $policy$
        create policy lagaw_destination_images_no_client_delete
        on storage.objects as restrictive for delete
        to anon, authenticated
        using (bucket_id <> 'destination-images')
    $policy$;
end;
$$;
