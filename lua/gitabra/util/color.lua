-- Ported from https://css-tricks.com/converting-color-spaces-in-javascript/
local function RGB_to_Hex(r, g, b)
  return string.format("#%02x%02x%02x", r, g, b)
end

local function Hex_to_RGB(hex)
  local r = tonumber(string.sub(hex, 2, 3), 16)
  local g = tonumber(string.sub(hex, 4, 5), 16)
  local b = tonumber(string.sub(hex, 6, 7), 16)

  return r, g, b
end

local function math_sign(v)
	return (v >= 0 and 1) or -1
end

local function math_round(v, bracket)
	bracket = bracket or 1
	return math.floor(v/bracket + math_sign(v) * 0.5) * bracket
end

local function RGB_to_HSL(r, g, b)
  r = r / 255
  g = g / 255
  b = b / 255

  -- Find greatest and smallest channel values
  local cmin = math.min(r,g,b)
  local cmax = math.max(r,g,b)
  local delta = cmax - cmin
  local h = 0
  local s = 0
  local l = 0

  -- Calculate hue
  -- No difference
  if delta == 0 then
    h = 0

  -- Red is max
  elseif cmax == r then
    h = ((g - b) / delta) % 6;

  -- Green is max
  elseif cmax == g then
    h = (b - r) / delta + 2;

  -- Blue is max
  else
    h = (r - g) / delta + 4;
  end

  h = math_round(h * 60);

  -- Make negative hues positive behind 360°
  if (h < 0) then
    h = h + 360
  end

  -- Calculate lightness
  l = (cmax + cmin) / 2

  -- Calculate saturation
  if delta == 0 then
    s = 0
  else
    s = delta / (1 - math.abs(2 * l - 1))
  end

  -- Multiply l and s by 100
  s = math.abs(s) * 100
  l = l * 100
  return h, s, l
end

local function HSL_to_RGB(h, s, l)
  s = s / 100
  l = l / 100

  local c = (1 - math.abs(2 * l - 1)) * s
  local x = c * (1 - math.abs((h / 60) % 2 - 1))
  local m = l - c/2
  local r = 0
  local g = 0
  local b = 0;

  if (0 <= h and h < 60) then
    r = c; g = x; b = 0;
  elseif (60 <= h and h < 120) then
    r = x; g = c; b = 0;
  elseif (120 <= h and h < 180) then
    r = 0; g = c; b = x;
  elseif (180 <= h and h < 240) then
    r = 0; g = x; b = c;
  elseif (240 <= h and h < 300) then
    r = x; g = 0; b = c;
  elseif (300 <= h and h < 360) then
    r = c; g = 0; b = x;
  end

  r = math_round((r + m) * 255)
  g = math_round((g + m) * 255)
  b = math_round((b + m) * 255)
  return r, g, b
end

return {
  RGB_to_Hex = RGB_to_Hex,
  Hex_to_RGB = Hex_to_RGB,
  RGB_to_HSL = RGB_to_HSL,
  HSL_to_RGB = HSL_to_RGB,
}
