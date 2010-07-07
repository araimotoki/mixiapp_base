require 'friend'

YAML::add_domain_type("cyworks.jp,2010", "Friend") do |type, val|
  Friend.new val
end
