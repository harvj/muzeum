import { Controller } from "@hotwired/stimulus"

const regions = { XW: "Worldwide", XE: "Europe", ZZ: "Country unavailable" }

export default class extends Controller {
  static values = { country: String }

  hideFlag(event) {
    event.target.closest(".geographic-flag").hidden = true
  }

  connect() {
    if (!this.hasCountryValue) return

    const code = this.countryValue.toUpperCase()
    if (regions[code]) {
      this.element.textContent = regions[code]
      return
    }
    if (!/^[A-Z]{2}$/.test(code)) {
      this.element.textContent = "Country unavailable"
      return
    }
    const names = new Intl.DisplayNames(document.documentElement.lang || "en", { type: "region", fallback: "none" })
    const name = names.of(code)
    if (!name) {
      this.element.textContent = "Country unavailable"
      return
    }

    const flag = document.createElement("span")
    flag.setAttribute("aria-hidden", "true")
    flag.textContent = [...code].map(letter => String.fromCodePoint(letter.charCodeAt(0) + 127397)).join("")
    this.element.replaceChildren(flag, document.createTextNode(` ${name}`))
  }
}
