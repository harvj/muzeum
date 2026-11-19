import { Controller } from "@hotwired/stimulus"

const failed = new Map()
const imageTimeout = 5000

export default class extends Controller {
  static values = { urls: Object }

  connect() {
    this.scheme = matchMedia("(prefers-color-scheme: dark)")
    this.updateBackground = () => this.showBackground()
    this.scheme.addEventListener("change", this.updateBackground)
    this.appearance = new MutationObserver(this.updateBackground)
    this.appearance.observe(document.documentElement, {
      attributes: true, attributeFilter: ["data-appearance"]
    })
    this.clearIcon = () => {
      this.iconLoad?.abort()
      this.icon?.remove()
    }
    document.addEventListener("turbo:before-render", this.clearIcon)
    this.showBackground()
    this.showIcon()
  }

  disconnect() {
    this.scheme.removeEventListener("change", this.updateBackground)
    this.appearance.disconnect()
    document.removeEventListener("turbo:before-render", this.clearIcon)
    this.clearIcon()
    this.backgroundLoad?.abort()
    this.background?.remove()
  }

  async showBackground() {
    const appearance = document.documentElement.dataset.appearance
    const theme = appearance === "light" || appearance === "dark"
      ? appearance : (this.scheme.matches ? "dark" : "light")
    const url = this.urlsValue[theme]
    if (url === this.backgroundURL) return

    this.backgroundURL = url
    this.backgroundLoad?.abort()
    this.background?.remove()
    const load = this.backgroundLoad = new AbortController()
    const image = await this.decode(theme, url, load.signal)
    if (!image || load.signal.aborted) return

    image.className = "site-art-background"
    image.alt = ""
    image.dataset.turboTemporary = ""
    this.background = image
    this.element.prepend(image)
  }

  async showIcon() {
    const url = this.urlsValue.favicon
    const load = this.iconLoad = new AbortController()
    const image = await this.decode("favicon", url, load.signal)
    if (!image || load.signal.aborted) return

    const icon = this.icon = document.createElement("link")
    icon.rel = "icon"
    icon.crossOrigin = "anonymous"
    icon.referrerPolicy = "no-referrer"
    if (url.endsWith(".svg")) icon.sizes = "any"
    icon.href = url
    icon.addEventListener("error", this.clearIcon, { once: true })
    document.head.append(icon)
  }

  async decode(slot, url, signal) {
    const failure = failed.get(slot)
    if (!url || (failure?.url === url && performance.now() < failure.retryAt)) return

    const image = new Image()
    image.crossOrigin = "anonymous"
    image.referrerPolicy = "no-referrer"
    image.fetchPriority = "low"
    const cancel = () => image.removeAttribute("src")
    signal.addEventListener("abort", cancel, { once: true })
    const timeout = setTimeout(cancel, imageTimeout)
    try {
      image.src = url
      await image.decode()
      failed.delete(slot)
      return image
    } catch (_) {
      if (!signal.aborted) failed.set(slot, { url, retryAt: performance.now() + 60000 })
    } finally {
      clearTimeout(timeout)
      signal.removeEventListener("abort", cancel)
    }
  }
}
