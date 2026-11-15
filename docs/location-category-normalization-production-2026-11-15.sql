-- Target ONLY production: https://zjnuqqtbapbpudsjbpif.supabase.co
-- Review qualified estimates and select the correct Supabase project before executing.
BEGIN;
DO $refresh_0$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM public.locations WHERE id = 'c6303987-1b9c-5a83-b80d-7a9a4b389b6b'::uuid AND name = 'Artfull Philippines / Gallery and Cafe' AND category IS NOT DISTINCT FROM 'gallery') THEN
    UPDATE public.locations SET category = 'gallery' WHERE id = 'c6303987-1b9c-5a83-b80d-7a9a4b389b6b'::uuid AND name = 'Artfull Philippines / Gallery and Cafe' AND category IS NOT DISTINCT FROM 'art_gallery';
    IF NOT FOUND THEN RAISE EXCEPTION 'Metadata target missing or edited'; END IF;
  END IF;
END; $refresh_0$;
DO $refresh_1$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM public.locations WHERE id = 'f5daa34a-7e4b-5a7e-9e97-1cf4d9c1c920'::uuid AND name = 'Lopue''s East Bowling Center' AND category IS NOT DISTINCT FROM 'recreation') THEN
    UPDATE public.locations SET category = 'recreation' WHERE id = 'f5daa34a-7e4b-5a7e-9e97-1cf4d9c1c920'::uuid AND name = 'Lopue''s East Bowling Center' AND category IS NOT DISTINCT FROM 'indoor_recreation';
    IF NOT FOUND THEN RAISE EXCEPTION 'Metadata target missing or edited'; END IF;
  END IF;
END; $refresh_1$;
DO $refresh_2$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM public.locations WHERE id = 'c4047367-665b-5a04-8fd1-44aa7e50aa56'::uuid AND name = 'May''s Organic Garden and Restaurant' AND category IS NOT DISTINCT FROM 'park') THEN
    UPDATE public.locations SET category = 'park' WHERE id = 'c4047367-665b-5a04-8fd1-44aa7e50aa56'::uuid AND name = 'May''s Organic Garden and Restaurant' AND category IS NOT DISTINCT FROM 'garden_farm_tourism';
    IF NOT FOUND THEN RAISE EXCEPTION 'Metadata target missing or edited'; END IF;
  END IF;
END; $refresh_2$;
DO $refresh_3$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM public.locations WHERE id = '43f712d8-a6bd-5113-905e-b8d00cf2c2f6'::uuid AND name = 'Quan Native Delicacies - Plaza' AND category IS NOT DISTINCT FROM 'restaurant') THEN
    UPDATE public.locations SET category = 'restaurant' WHERE id = '43f712d8-a6bd-5113-905e-b8d00cf2c2f6'::uuid AND name = 'Quan Native Delicacies - Plaza' AND category IS NOT DISTINCT FROM 'local_food';
    IF NOT FOUND THEN RAISE EXCEPTION 'Metadata target missing or edited'; END IF;
  END IF;
END; $refresh_3$;
DO $refresh_4$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM public.locations WHERE id = '5509d004-3126-5c89-942a-b1ccc4f742a8'::uuid AND name = 'The Negros Showroom - South Capitol Road' AND category IS NOT DISTINCT FROM 'shopping') THEN
    UPDATE public.locations SET category = 'shopping' WHERE id = '5509d004-3126-5c89-942a-b1ccc4f742a8'::uuid AND name = 'The Negros Showroom - South Capitol Road' AND category IS NOT DISTINCT FROM 'crafts_souvenirs';
    IF NOT FOUND THEN RAISE EXCEPTION 'Metadata target missing or edited'; END IF;
  END IF;
END; $refresh_4$;
DO $refresh_5$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM public.locations WHERE id = 'f2ee9da3-4f32-50d5-9840-f6352bfccc9a'::uuid AND name = 'Coffee Culture Roastery - Alijis' AND category IS NOT DISTINCT FROM 'cafe') THEN
    UPDATE public.locations SET category = 'cafe' WHERE id = 'f2ee9da3-4f32-50d5-9840-f6352bfccc9a'::uuid AND name = 'Coffee Culture Roastery - Alijis' AND category IS NOT DISTINCT FROM 'cafe';
    IF NOT FOUND THEN RAISE EXCEPTION 'Metadata target missing or edited'; END IF;
  END IF;
END; $refresh_5$;
DO $refresh_6$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM public.locations WHERE id = '0bf1a140-9303-508f-9375-a2ceabce77f3'::uuid AND name = 'Manokan Country - temporary SM site' AND category IS NOT DISTINCT FROM 'restaurant') THEN
    UPDATE public.locations SET category = 'restaurant' WHERE id = '0bf1a140-9303-508f-9375-a2ceabce77f3'::uuid AND name = 'Manokan Country - temporary SM site' AND category IS NOT DISTINCT FROM 'local_food';
    IF NOT FOUND THEN RAISE EXCEPTION 'Metadata target missing or edited'; END IF;
  END IF;
END; $refresh_6$;
DO $refresh_7$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM public.locations WHERE id = '69e4f350-bd25-50e8-90f0-24eea097f91d'::uuid AND name = 'Pope John Paul II Tower' AND category IS NOT DISTINCT FROM 'heritage') THEN
    UPDATE public.locations SET category = 'heritage' WHERE id = '69e4f350-bd25-50e8-90f0-24eea097f91d'::uuid AND name = 'Pope John Paul II Tower' AND category IS NOT DISTINCT FROM 'heritage_viewpoint';
    IF NOT FOUND THEN RAISE EXCEPTION 'Metadata target missing or edited'; END IF;
  END IF;
END; $refresh_7$;
DO $refresh_8$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM public.locations WHERE id = '49f18097-4d77-5237-8f28-cfd4a0b5940a'::uuid AND name = 'kidzooona - SM City Bacolod' AND category IS NOT DISTINCT FROM 'recreation') THEN
    UPDATE public.locations SET category = 'recreation' WHERE id = '49f18097-4d77-5237-8f28-cfd4a0b5940a'::uuid AND name = 'kidzooona - SM City Bacolod' AND category IS NOT DISTINCT FROM 'childrens_play';
    IF NOT FOUND THEN RAISE EXCEPTION 'Metadata target missing or edited'; END IF;
  END IF;
END; $refresh_8$;
DO $refresh_9$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM public.locations WHERE id = 'eeeb59c9-b5d6-58ca-aa54-ce33c221a222'::uuid AND name = 'Ayala Malls Capitol Central - general visit' AND category IS NOT DISTINCT FROM 'shopping') THEN
    UPDATE public.locations SET category = 'shopping' WHERE id = 'eeeb59c9-b5d6-58ca-aa54-ce33c221a222'::uuid AND name = 'Ayala Malls Capitol Central - general visit' AND category IS NOT DISTINCT FROM 'shopping_leisure';
    IF NOT FOUND THEN RAISE EXCEPTION 'Metadata target missing or edited'; END IF;
  END IF;
END; $refresh_9$;
DO $refresh_10$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM public.locations WHERE id = 'e36ca062-fbf0-5e4b-b6bd-24f61d3e5a99'::uuid AND name = 'Timezone - Ayala Malls Capitol Central' AND category IS NOT DISTINCT FROM 'recreation') THEN
    UPDATE public.locations SET category = 'recreation' WHERE id = 'e36ca062-fbf0-5e4b-b6bd-24f61d3e5a99'::uuid AND name = 'Timezone - Ayala Malls Capitol Central' AND category IS NOT DISTINCT FROM 'arcade_recreation';
    IF NOT FOUND THEN RAISE EXCEPTION 'Metadata target missing or edited'; END IF;
  END IF;
END; $refresh_10$;
DO $refresh_11$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM public.locations WHERE id = 'a9e26ed9-83bb-5056-907a-85b699448eec'::uuid AND name = 'Caribbean Waterpark and Resotel - day use' AND category IS NOT DISTINCT FROM 'resort') THEN
    UPDATE public.locations SET category = 'resort' WHERE id = 'a9e26ed9-83bb-5056-907a-85b699448eec'::uuid AND name = 'Caribbean Waterpark and Resotel - day use' AND category IS NOT DISTINCT FROM 'waterpark';
    IF NOT FOUND THEN RAISE EXCEPTION 'Metadata target missing or edited'; END IF;
  END IF;
END; $refresh_11$;
DO $refresh_12$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM public.locations WHERE id = 'a22c5862-5ce7-5793-a96e-150b79e1f2af'::uuid AND name = 'Resorts Negrense - day use' AND category IS NOT DISTINCT FROM 'resort') THEN
    UPDATE public.locations SET category = 'resort' WHERE id = 'a22c5862-5ce7-5793-a96e-150b79e1f2af'::uuid AND name = 'Resorts Negrense - day use' AND category IS NOT DISTINCT FROM 'coastal_day_resort';
    IF NOT FOUND THEN RAISE EXCEPTION 'Metadata target missing or edited'; END IF;
  END IF;
END; $refresh_12$;
DO $refresh_13$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM public.locations WHERE id = '8bc43864-3bad-5326-9c11-53b1eb274571'::uuid AND name = 'Merzci - Sum-ag branch' AND category IS NOT DISTINCT FROM 'shopping') THEN
    UPDATE public.locations SET category = 'shopping' WHERE id = '8bc43864-3bad-5326-9c11-53b1eb274571'::uuid AND name = 'Merzci - Sum-ag branch' AND category IS NOT DISTINCT FROM 'pasalubong_food';
    IF NOT FOUND THEN RAISE EXCEPTION 'Metadata target missing or edited'; END IF;
  END IF;
END; $refresh_13$;
DO $refresh_14$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM public.locations WHERE id = '4ce87f7b-17d1-538f-8a1e-408956bdbb64'::uuid AND name = 'Sharyn''s Cansi House - Narra' AND category IS NOT DISTINCT FROM 'restaurant') THEN
    UPDATE public.locations SET category = 'restaurant' WHERE id = '4ce87f7b-17d1-538f-8a1e-408956bdbb64'::uuid AND name = 'Sharyn''s Cansi House - Narra' AND category IS NOT DISTINCT FROM 'local_food';
    IF NOT FOUND THEN RAISE EXCEPTION 'Metadata target missing or edited'; END IF;
  END IF;
END; $refresh_14$;
DO $refresh_15$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM public.locations WHERE id = 'ace4cd5a-e098-545e-bd2b-bfa19e529782'::uuid AND name = 'Aboy''s Restaurant - Liroville' AND category IS NOT DISTINCT FROM 'restaurant') THEN
    UPDATE public.locations SET category = 'restaurant' WHERE id = 'ace4cd5a-e098-545e-bd2b-bfa19e529782'::uuid AND name = 'Aboy''s Restaurant - Liroville' AND category IS NOT DISTINCT FROM 'local_food';
    IF NOT FOUND THEN RAISE EXCEPTION 'Metadata target missing or edited'; END IF;
  END IF;
END; $refresh_15$;
DO $refresh_16$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM public.locations WHERE id = '977ea9ef-dafe-5986-9efc-79c611ff9f6c'::uuid AND name = 'Palawud Resto Grill and Bar - San Juan/Banago' AND category IS NOT DISTINCT FROM 'restaurant') THEN
    UPDATE public.locations SET category = 'restaurant' WHERE id = '977ea9ef-dafe-5986-9efc-79c611ff9f6c'::uuid AND name = 'Palawud Resto Grill and Bar - San Juan/Banago' AND category IS NOT DISTINCT FROM 'seaside_dining';
    IF NOT FOUND THEN RAISE EXCEPTION 'Metadata target missing or edited'; END IF;
  END IF;
END; $refresh_16$;
DO $refresh_17$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM public.locations WHERE id = '24d858ec-8cf1-53c6-ab55-97858a5fed88'::uuid AND name = 'Kuppa Coffee and Tea - Tindalo' AND category IS NOT DISTINCT FROM 'cafe') THEN
    UPDATE public.locations SET category = 'cafe' WHERE id = '24d858ec-8cf1-53c6-ab55-97858a5fed88'::uuid AND name = 'Kuppa Coffee and Tea - Tindalo' AND category IS NOT DISTINCT FROM 'cafe_meals';
    IF NOT FOUND THEN RAISE EXCEPTION 'Metadata target missing or edited'; END IF;
  END IF;
END; $refresh_17$;
DO $refresh_18$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM public.locations WHERE id = '70b981f6-8196-5546-b0ce-0ab1773fbac4'::uuid AND name = 'Fully Booked - SM City Bacolod' AND category IS NOT DISTINCT FROM 'shopping') THEN
    UPDATE public.locations SET category = 'shopping' WHERE id = '70b981f6-8196-5546-b0ce-0ab1773fbac4'::uuid AND name = 'Fully Booked - SM City Bacolod' AND category IS NOT DISTINCT FROM 'bookstore_leisure';
    IF NOT FOUND THEN RAISE EXCEPTION 'Metadata target missing or edited'; END IF;
  END IF;
END; $refresh_18$;
DO $refresh_19$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM public.locations WHERE id = '3c897dde-3ad4-5599-87d6-6fa234136748'::uuid AND name = 'Negros Superlanes - Goldenfield' AND category IS NOT DISTINCT FROM 'recreation') THEN
    UPDATE public.locations SET category = 'recreation' WHERE id = '3c897dde-3ad4-5599-87d6-6fa234136748'::uuid AND name = 'Negros Superlanes - Goldenfield' AND category IS NOT DISTINCT FROM 'evening_bowling';
    IF NOT FOUND THEN RAISE EXCEPTION 'Metadata target missing or edited'; END IF;
  END IF;
END; $refresh_19$;
COMMIT;
