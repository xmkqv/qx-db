-- Create a public profiles table
CREATE TABLE public.profiles (
id UUID REFERENCES auth.users(id) ON DELETE CASCADE PRIMARY KEY,
username TEXT UNIQUE,
full_name TEXT,
avatar_url TEXT,
bio TEXT,
created_at TIMESTAMPTZ DEFAULT NOW(),
updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Enable RLS
ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;

-- Users can read all profiles
CREATE POLICY "Profiles are viewable by everyone"
ON public.profiles FOR SELECT
USING (true);

-- Users can only update their own profile
CREATE POLICY "Users can update own profile"
ON public.profiles FOR UPDATE
USING (auth.uid() = id);
