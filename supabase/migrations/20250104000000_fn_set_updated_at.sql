-- Standard updated_at trigger function
CREATE OR REPLACE FUNCTION fn_trigger_set_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;
