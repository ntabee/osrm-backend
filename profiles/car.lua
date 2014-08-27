-- Begin of globals
--require("lib/access") --function temporarily inlined

barrier_whitelist = { ["cattle_grid"] = true, ["border_control"] = true, ["toll_booth"] = true, ["sally_port"] = true, ["gate"] = true, ["no"] = true, ["entrance"] = true }
access_tag_whitelist = { ["yes"] = true, ["motorcar"] = true, ["motor_vehicle"] = true, ["vehicle"] = true, ["permissive"] = true, ["designated"] = true }
access_tag_blacklist = { ["no"] = true, ["private"] = true, ["agricultural"] = true, ["forestry"] = true, ["emergency"] = true }
access_tag_restricted = { ["destination"] = true, ["delivery"] = true }
access_tags = { "motorcar", "motor_vehicle", "vehicle" }
access_tags_hierachy = { "motorcar", "motor_vehicle", "vehicle", "access" }
service_tag_restricted = { ["parking_aisle"] = true }
ignore_in_grid = { ["ferry"] = true }
restriction_exception_tags = { "motorcar", "motor_vehicle", "vehicle" }

speed_profile = {
  ["motorway"] = 90,
  ["motorway_link"] = 75,
  ["trunk"] = 85,
  ["trunk_link"] = 70,
  ["primary"] = 65,
  ["primary_link"] = 60,
  ["secondary"] = 55,
  ["secondary_link"] = 50,
  ["tertiary"] = 40,
  ["tertiary_link"] = 30,
  ["unclassified"] = 25,
  ["residential"] = 25,
  ["living_street"] = 10,
  ["service"] = 15,
--  ["track"] = 5,
  ["ferry"] = 5,
  ["shuttle_train"] = 10,
  ["default"] = 10
}

traffic_signal_penalty          = 2

-- End of globals
local take_minimum_of_speeds    = false
local obey_oneway               = true
local obey_bollards             = true
local use_turn_restrictions     = true
local ignore_areas              = true     -- future feature
local u_turn_penalty            = 20

local abs = math.abs
local min = math.min
local max = math.max

local speed_reduction = 0.8

--modes
local mode_normal = 1
local mode_ferry = 2

local function find_access_tag(source, access_tags_hierachy)
  for i,v in ipairs(access_tags_hierachy) do
    local access_tag = source:get_value_by_key(v)
    if access_tag and "" ~= access_tag then
      return access_tag
    end
  end
  return ""
end

function get_exceptions(vector)
  for i,v in ipairs(restriction_exception_tags) do
    vector:Add(v)
  end
end

local function parse_maxspeed(source)
  if not source then
    return 0
  end
  local n = tonumber(source:match("%d*"))
  if not n then
    n = 0
  end
  if string.match(source, "mph") or string.match(source, "mp/h") then
    n = (n*1609)/1000;
  end
  return n
end

-- function turn_function (angle)
--   -- print ("called at angle " .. angle )
--   local index = math.abs(math.floor(angle/10+0.5))+1 -- +1 'coz LUA starts as idx 1
--   local penalty = turn_cost_table[index]
--   -- print ("index: " .. index .. ", bias: " .. penalty )
--   return penalty
-- end

function node_function (node, result)
  -- parse access and barrier tags
  local access = find_access_tag(node, access_tags_hierachy)
  if access ~= "" then
    if access_tag_blacklist[access] then
      result.barrier = true
    end
  else
    local barrier = node:get_value_by_key("barrier")
    if barrier and "" ~= barrier then
      if barrier_whitelist[barrier] then
        return
      else
        result.barrier = true
      end
    end
  end

  -- check if node is a traffic light
  local tag = node:get_value_by_key("highway")
  if tag and "traffic_signals" == tag then
    result.traffic_lights = true;
  end
end

function way_function (way, result)
  local highway = way:get_value_by_key("highway")
  local route = way:get_value_by_key("route")

  if not ((highway and highway ~= "") or (route and route ~= "")) then
    return
  end

  -- we dont route over areas
  local area = way:get_value_by_key("area")
  if ignore_areas and area and "yes" == area then
    return
  end

  -- check if oneway tag is unsupported
  local oneway = way:get_value_by_key("oneway")
  if oneway and "reversible" == oneway then
    return
  end

  local impassable = way:get_value_by_key("impassable")
  if impassable and "yes" == impassable then
    return
  end

  local status = way:get_value_by_key("status")
  if status and "impassable" == status then
    return
  end

  -- Check if we are allowed to access the way
  local access = find_access_tag(way, access_tags_hierachy)
  if access_tag_blacklist[access] then
    return
  end

  -- Handling ferries and piers
  local route_speed = speed_profile[route]
  if(route_speed and route_speed > 0) then
    highway = route;
    local duration  = way:get_value_by_key("duration")
    if duration and durationIsValid(duration) then
      result.duration = max( parseDuration(duration), 1 );
    end
    result.forward_mode = mode_ferry
    result.backward_mode = mode_ferry
    result.forward_speed = route_speed
    result.backward_speed = route_speed
  end

  -- leave early of this way is not accessible
  if "" == highway then
    return
  end

  if result.forward_speed == -1 then
    local highway_speed = speed_profile[highway]
    local max_speed = parse_maxspeed( way:get_value_by_key("maxspeed") )
    -- Set the avg speed on the way if it is accessible by road class
    if highway_speed then
      if max_speed and max_speed > highway_speed then
        result.forward_speed = max_speed
        result.backward_speed = max_speed
        -- max_speed = math.huge
      else
        result.forward_speed = highway_speed
        result.backward_speed = highway_speed
      end
    else
      -- Set the avg speed on ways that are marked accessible
      if access_tag_whitelist[access] then
        result.forward_speed = speed_profile["default"]
        result.backward_speed = speed_profile["default"]
      end
    end
    if 0 == max_speed then
      max_speed = math.huge
    end
    result.forward_speed = min(result.forward_speed, max_speed)
    result.backward_speed = min(result.backward_speed, max_speed)
  end

  if -1 == result.forward_speed and -1 == result.backward_speed then
    return
  end

  -- parse the remaining tags
  local name = way:get_value_by_key("name")
  local ref = way:get_value_by_key("ref")
  local junction = way:get_value_by_key("junction")
  -- local barrier = way:get_value_by_key("barrier", "")
  -- local cycleway = way:get_value_by_key("cycleway", "")
  local service = way:get_value_by_key("service")

  -- Set the name that will be used for instructions
  if ref and "" ~= ref then
    result.name = ref
  elseif name and "" ~= name then
    result.name = name
--  else
      --    result.name = highway  -- if no name exists, use way type
  end

  if junction and "roundabout" == junction then
    result.roundabout = true;
  end

  -- Set access restriction flag if access is allowed under certain restrictions only
  if access ~= "" and access_tag_restricted[access] then
    result.is_access_restricted = true
  end

  -- Set access restriction flag if service is allowed under certain restrictions only
  if service and service ~= "" and service_tag_restricted[service] then
    result.is_access_restricted = true
  end

  -- Set direction according to tags on way
  if obey_oneway then
    if oneway == "-1" then
      result.forward_mode = 0
    elseif oneway == "yes" or
    oneway == "1" or
    oneway == "true" or
    junction == "roundabout" or
    (highway == "motorway_link" and oneway ~="no") or
    (highway == "motorway" and oneway ~= "no") then
      result.backward_mode = 0
    end
  end

  -- Override speed settings if explicit forward/backward maxspeeds are given
  local maxspeed_forward = parse_maxspeed(way:get_value_by_key( "maxspeed:forward"))
  local maxspeed_backward = parse_maxspeed(way:get_value_by_key( "maxspeed:backward"))
  if maxspeed_forward and maxspeed_forward > 0 then
    if 0 ~= result.forward_mode and 0 ~= result.backward_mode then
      result.backward_speed = result.forward_speed
    end
    result.forward_speed = maxspeed_forward
  end
  if maxspeed_backward and maxspeed_backward > 0 then
    result.backward_speed = maxspeed_backward
  end

  -- Override general direction settings of there is a specific one for our mode of travel
  if ignore_in_grid[highway] then
    result.ignore_in_grid = true
  end

  -- scale speeds to get better avg driving times
  if result.forward_speed > 0 then
    result.forward_speed = result.forward_speed*speed_reduction
  end
  if result.backward_speed > 0 then
    result.backward_speed = result.backward_speed*speed_reduction
  end
end

-- These are wrappers to parse vectors of nodes and ways and thus to speed up any tracing JIT
function node_vector_function(vector)
  for v in vector.nodes do
    node_function(v)
  end
end
