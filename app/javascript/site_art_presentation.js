const palette = { light: "#F1F2ED", dark: "#292D2C" }
const white = [255, 255, 255]
const black = [0, 0, 0]

function channels(hex) {
  return hex.slice(1).match(/../g).map(value => parseInt(value, 16))
}

function luminance(rgb) {
  const linear = rgb.map(channel => {
    const value = channel / 255
    return value <= 0.04045 ? value / 12.92 : ((value + 0.055) / 1.055) ** 2.4
  })
  return 0.2126 * linear[0] + 0.7152 * linear[1] + 0.0722 * linear[2]
}

function contrast(first, second) {
  return (Math.max(first, second) + 0.05) / (Math.min(first, second) + 0.05)
}

function mix(top, bottom, opacity) {
  return top.map((channel, index) => channel * opacity + bottom[index] * (1 - opacity))
}

function color(rgb, percent) {
  return `rgb(${rgb.join(" ")} / ${percent}%)`
}

export function artworkTreatment(record, theme, region) {
  const { regions, ...base } = record.presentation || {}
  const treatment = { ...base, ...regions?.[region] }
  if (!Object.keys(treatment).length && !record.foreground) return {}
  const { foreground, text_shadow: shadow, backing } = treatment
  const text = foreground || palette[record.foreground || (theme === "dark" ? "light" : "dark")]
  const tint = backing ? channels(backing.color) : black
  const opacity = (backing?.opacity_percent || 0) / 100
  const textLightness = luminance(channels(text))

  // Check both extremes so the overlay stays readable at any crop, even during illumination.
  for (let percent = 0; percent <= 100; percent += 5) {
    for (const neutral of [white, black]) {
      const darkest = luminance(mix(tint, mix(neutral, black, percent / 100), opacity))
      const lightest = luminance(mix(tint, mix(neutral, white, percent / 100), opacity))
      const nearest = Math.max(darkest, Math.min(lightest, textLightness))
      if (contrast(textLightness, nearest) < 4.55) continue

      return {
        foreground: text,
        shadow: shadow && `${shadow.x_px}px ${shadow.y_px}px ${shadow.blur_px}px ${color(channels(shadow.color), shadow.opacity_percent)}`,
        backing: backing && color(tint, backing.opacity_percent),
        scrim: color(neutral, percent)
      }
    }
  }

  return { foreground: "var(--ink)", scrim: "var(--card)" }
}
