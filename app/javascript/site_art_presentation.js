const legacyPalette = { light: "#F1F2ED", dark: "#292D2C" }

function color(effect) {
  const channels = effect.color.slice(1).match(/../g).map(value => parseInt(value, 16))
  return `rgb(${channels.join(" ")} / ${effect.opacity_percent}%)`
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
