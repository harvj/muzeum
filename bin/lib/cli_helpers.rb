def usage!
  abort USAGE
end

def parse_surface_id!(arg)
  abort "expected sid:<id>" unless arg&.start_with?("sid:")
  arg.delete_prefix("sid:").to_i
end
