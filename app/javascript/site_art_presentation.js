const legacyPalette = { light: "#F1F2ED", dark: "#292D2C" }

function channels(hex) {
  return hex.slice(1).match(/../g).map(value => parseInt(value, 16))
}

function color(effect) {
  return `rgb(${channels(effect.color).join(" ")} / ${effect.opacity_percent}%)`
}

function linear(value) {
  return value <= 0.04045 ? value / 12.92 : ((value + 0.055) / 1.055) ** 2.4
}

function srgb(value) {
  return value <= 0.0031308 ? 12.92 * value : 1.055 * value ** (1 / 2.4) - 0.055
}

// Choose a neutral surface that meets AA even over the brightest or darkest pixel.
export function readingSurface(foreground) {
  const [red, green, blue] = channels(foreground).map(value => linear(value / 255))
  const luminance = 0.2126 * red + 0.7152 * green + 0.0722 * blue
  const dark = (luminance + 0.05) / 0.05 >= 1.05 / (luminance + 0.05)
  const ratio = 4.5
  const limit = dark ? (luminance + 0.05) / ratio - 0.05 : (luminance + 0.05) * ratio - 0.05
  const opacity = Math.ceil((dark ? 1 - srgb(limit) : srgb(limit)) * 100)
  const neutral = dark ? "0 0 0" : "255 255 255"
  return `rgb(${neutral} / ${opacity}%)`
}

// Rails projects only validated fields from the published manifest.
export function artworkTreatment(record, role) {
  const flat = record.presentation
  const region = role === "default" ? undefined : flat?.regions?.[role]
  const foreground = region?.foreground ?? flat?.foreground ?? legacyPalette[record.foreground]
  const shadow = region?.text_shadow ?? flat?.text_shadow
  const backing = region?.backing ?? flat?.backing

  return {
    foreground: foreground?.toUpperCase(),
    "text-shadow": shadow && (shadow.opacity_percent === 0 ? "none" :
      `${shadow.x_px}px ${shadow.y_px}px ${shadow.blur_px}px ${color(shadow)}`),
    backing: backing && (backing.opacity_percent === 0 ? "transparent" : color(backing))
  }
}
