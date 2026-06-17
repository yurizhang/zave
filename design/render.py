import asyncio
from playwright.async_api import async_playwright

HTML = "file:///sessions/cool-sweet-allen/mnt/filemanager/design/html/file-manager.html"
OUT = "/sessions/cool-sweet-allen/mnt/filemanager/design/UI"

async def shot(page, name, setup=None):
    if setup:
        await setup(page)
    await page.wait_for_timeout(500)
    await page.screenshot(path=f"{OUT}/{name}", full_page=True)
    print("saved", name)

async def main():
    async with async_playwright() as p:
        b = await p.chromium.launch(
            executable_path="/sessions/cool-sweet-allen/.cache/ms-playwright/chromium-1223/chrome-linux/chrome",
            args=["--force-color-profile=srgb","--no-sandbox"])
        pg = await b.new_page(viewport={"width":1204,"height":640}, device_scale_factor=2)
        await pg.goto(HTML, wait_until="networkidle")
        await pg.evaluate("document.fonts.ready")
        await pg.wait_for_timeout(800)

        # 1. light + list (default)
        await shot(pg, "01-light-list.png")

        # 2. light + grid
        async def grid(pg): await pg.click('.vbtn[data-view="grid"]')
        await shot(pg, "02-light-grid.png", grid)

        # 3. dark + list
        async def dark(pg):
            await pg.click('.vbtn[data-view="list"]')
            await pg.click('#themeBtn')
        await shot(pg, "03-dark-list.png", dark)

        await b.close()

asyncio.run(main())
print("done")
