-- Target ONLY production: https://zjnuqqtbapbpudsjbpif.supabase.co
-- Review qualified estimates and select the correct Supabase project before executing.
BEGIN;
DO $refresh_0$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM public.locations WHERE id = 'a752a30a-1859-503d-8a77-8cd59097ac1d'::uuid AND name = 'Cafetolyo Coffee Shop' AND description IS NOT DISTINCT FROM 'A coffee and light-refreshment stop at the provincial capitol park, associated with locally sourced coffee and casual breaks. Reported hours and PHP 70-120 spending estimate are reported on the official Facebook page; Sunday access is unspecified. Prices are indicative, not guaranteed total spending.') THEN
    UPDATE public.locations SET description = 'A coffee and light-refreshment stop at the provincial capitol park, associated with locally sourced coffee and casual breaks. Reported hours and PHP 70-120 spending estimate are reported on the official Facebook page; Sunday access is unspecified. Prices are indicative, not guaranteed total spending.' WHERE id = 'a752a30a-1859-503d-8a77-8cd59097ac1d'::uuid AND name = 'Cafetolyo Coffee Shop' AND description IS NOT DISTINCT FROM 'A coffee and light-refreshment stop at the provincial capitol park, associated with locally sourced coffee and casual breaks. Reported hours and PHP 70-120 spending estimate were supplied by Andrew from the official Facebook page; Sunday access is unspecified. Prices are indicative, not guaranteed total spending.';
    IF NOT FOUND THEN RAISE EXCEPTION 'Metadata target missing or edited'; END IF;
  END IF;
END; $refresh_0$;
DO $refresh_1$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM public.locations WHERE id = 'f2ccf475-56ea-51a0-a003-70f66d9f852a'::uuid AND name = 'Calea Pastries & Coffee' AND description IS NOT DISTINCT FROM 'A Bacolod pastry and dessert café on 15th Street offering a stop for cakes and coffee. The reported PHP 95-1,100 menu-price range includes different products such as slices and whole cakes; it is an indicative purchase allowance, not a fixed per-person meal or admission price. Hours and branch pin await independent confirmation.') THEN
    UPDATE public.locations SET description = 'A Bacolod pastry and dessert café on 15th Street offering a stop for cakes and coffee. The reported PHP 95-1,100 menu-price range includes different products such as slices and whole cakes; it is an indicative purchase allowance, not a fixed per-person meal or admission price. Hours and branch pin await independent confirmation.' WHERE id = 'f2ccf475-56ea-51a0-a003-70f66d9f852a'::uuid AND name = 'Calea Pastries & Coffee' AND description IS NOT DISTINCT FROM 'A Bacolod pastry and dessert café on 15th Street offering a stop for cakes and coffee. The supplied PHP 95-1,100 menu-price range includes different products such as slices and whole cakes; it is an indicative purchase allowance, not a fixed per-person meal or admission price. Hours and branch pin are user-supplied.';
    IF NOT FOUND THEN RAISE EXCEPTION 'Metadata target missing or edited'; END IF;
  END IF;
END; $refresh_1$;
DO $refresh_2$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM public.locations WHERE id = '4618dfae-4a30-5917-85f1-94f216cf5b97'::uuid AND name = 'Negros Occidental Provincial Capitol' AND description IS NOT DISTINCT FROM 'The provincial government’s prominent capitol building, an architectural focal point of central Bacolod. Reported schedule: Tuesday-Friday 08:00-19:00, citing the provincial government website; these may be office hours rather than confirmed tourist access hours. Entrance is reported as free; visitor access and admission are not independently verified.') THEN
    UPDATE public.locations SET description = 'The provincial government’s prominent capitol building, an architectural focal point of central Bacolod. Reported schedule: Tuesday-Friday 08:00-19:00, citing the provincial government website; these may be office hours rather than confirmed tourist access hours. Entrance is reported as free; visitor access and admission are not independently verified.' WHERE id = '4618dfae-4a30-5917-85f1-94f216cf5b97'::uuid AND name = 'Negros Occidental Provincial Capitol' AND description IS NOT DISTINCT FROM 'The provincial government’s prominent capitol building, an architectural focal point of central Bacolod. Andrew-supplied schedule: Tuesday-Friday 08:00-19:00, citing the provincial government website; these may be office hours rather than confirmed tourist access hours. Andrew reports free entrance; visitor access and admission are not independently verified.';
    IF NOT FOUND THEN RAISE EXCEPTION 'Metadata target missing or edited'; END IF;
  END IF;
END; $refresh_2$;
DO $refresh_3$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM public.locations WHERE id = 'ee2c8f6e-7a15-5081-b8a3-b43d48d5a83c'::uuid AND name = 'Panaad Park and Sports Complex' AND description IS NOT DISTINCT FROM 'A provincial park and sports venue in Mansilingan used for major local events and the Panaad sa Negros Festival. Unverified Reddit reports: 04:00-20:00 daily and PHP 0-25 estimated admission. Reported oval fees are PHP 25 regular and PHP 15 student; they may not apply to the whole park. Hours and fees await confirmation.') THEN
    UPDATE public.locations SET description = 'A provincial park and sports venue in Mansilingan used for major local events and the Panaad sa Negros Festival. Unverified Reddit reports: 04:00-20:00 daily and PHP 0-25 estimated admission. Reported oval fees are PHP 25 regular and PHP 15 student; they may not apply to the whole park. Hours and fees await confirmation.' WHERE id = 'ee2c8f6e-7a15-5081-b8a3-b43d48d5a83c'::uuid AND name = 'Panaad Park and Sports Complex' AND description IS NOT DISTINCT FROM 'A provincial park and sports venue in Mansilingan used for major local events and the Panaad sa Negros Festival. Andrew-supplied, unverified Reddit reports: 04:00-20:00 daily and PHP 0-25 estimated admission. Reported oval fees are PHP 25 regular and PHP 15 student; they may not apply to the whole park. Hours and fees await confirmation.';
    IF NOT FOUND THEN RAISE EXCEPTION 'Metadata target missing or edited'; END IF;
  END IF;
END; $refresh_3$;
COMMIT;
