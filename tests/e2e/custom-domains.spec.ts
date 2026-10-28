import { expect, test, type BrowserContext } from '@playwright/test'
import { request as httpRequest, type IncomingHttpHeaders } from 'node:http'

const proxyPort = Number(process.env.SCD_MOCK_PROXY_PORT ?? '80')

// In production a customer's domain is HTTPS, and SaaS Custom Domains
// tells the app so with X-Forwarded-Proto: https. The mock sends the
// same header but speaks plain HTTP, so the browser here is on
// http://<name>.test. For form posts, send what a browser on
// https://<name>.test would send (that Origin is what Rails' CSRF check
// compares), and map the https:// redirect that comes back to http://.
// The redirects the app sent are kept in `redirects`.
const redirects: string[] = []

async function postLikeHttps(context: BrowserContext) {
  await context.route(/^http:\/\/[^/]+\.test(\/|$)/, async (route) => {
    const req = route.request()
    if (req.method() !== 'POST') return route.fallback()

    const headers = await req.allHeaders()
    if (headers.origin) headers.origin = headers.origin.replace(/^http:/, 'https:')
    const res = await proxyRequest('POST', req.url(), headers, req.postDataBuffer())
    if (res.headers.location) {
      redirects.push(res.headers.location)
      res.headers.location = res.headers.location.replace(/^https:/, 'http:')
    }
    await route.fulfill(res)
  })
}

// A plain HTTP proxy request to the mock: "POST http://acme.test/path".
function proxyRequest(
  method: string,
  url: string,
  headers: Record<string, string>,
  body: Buffer | null,
): Promise<{ status: number; headers: Record<string, string>; body: Buffer }> {
  return new Promise((resolve, reject) => {
    const req = httpRequest(
      { host: '127.0.0.1', port: proxyPort, method, path: url, headers },
      (res) => {
        const chunks: Buffer[] = []
        res.on('data', (c) => chunks.push(c))
        res.on('end', () =>
          resolve({
            status: res.statusCode!,
            headers: flatten(res.headers),
            body: Buffer.concat(chunks),
          }),
        )
      },
    )
    req.on('error', reject)
    req.end(body ?? undefined)
  })
}

function flatten(headers: IncomingHttpHeaders) {
  return Object.fromEntries(
    Object.entries(headers).map(([k, v]) => [
      k,
      Array.isArray(v) ? v.join('\n') : String(v),
    ]),
  )
}

const customerUrl = (host: string) => `http://${host}/`

test.beforeEach(async ({ context }) => postLikeHttps(context))

test('connect a domain, serve the status page through the proxy, remove it', async ({
  page,
}) => {
  const host = `acme-${Date.now()}.test`
  const company = page.getByTestId('company-acme')

  await page.goto('/')
  await company.getByLabel('Domain', { exact: true }).fill(host)
  await company.getByRole('button', { name: 'Add domain' }).click()
  const row = page.getByTestId(`domain-${host}`)
  await expect(row).toBeVisible()

  // The mock marks *.test as pointed after ~2s and sends webhooks.
  await expect(async () => {
    await page.reload()
    await expect(row).toContainText('Live')
  }).toPass({ timeout: 15_000 })

  await page.goto(customerUrl(host))
  await expect(page.getByRole('heading', { name: 'Acme Cloud status' })).toBeVisible()
  await expect(page.getByText(`Served on ${host}`)).toBeVisible()

  // A form on the customer's domain: passes the CSRF origin check, and
  // the redirect afterwards stays on the customer's domain.
  await page.getByLabel('Email').fill('reader@example.com')
  await page.getByRole('button', { name: 'Subscribe' }).click()
  await expect(page.getByRole('status')).toHaveText('Subscribed to Acme Cloud updates.')
  expect(redirects).toContain(`https://${host}/`)
  expect(page.url()).toBe(customerUrl(host))

  await page.goto('/')
  await row.getByRole('button', { name: 'Remove' }).click()
  await expect(async () => {
    await page.reload()
    await expect(row).toBeHidden()
  }).toPass({ timeout: 10_000 })
  const gone = await page.goto(customerUrl(host))
  expect(gone?.status()).toBe(404)
})

test('a domain that does not point at us stays pending', async ({ page }) => {
  const host = `status-${Date.now()}.example.com`
  const company = page.getByTestId('company-globex')

  await page.goto('/')
  await company.getByLabel('Domain', { exact: true }).fill(host)
  await company.getByRole('button', { name: 'Add domain' }).click()
  const row = page.getByTestId(`domain-${host}`)
  await row.getByRole('button', { name: 'Check DNS' }).click()
  await expect(row).toContainText('Waiting for DNS')

  await row.getByRole('button', { name: 'Remove' }).click()
  await expect(async () => {
    await page.reload()
    await expect(row).toBeHidden()
  }).toPass({ timeout: 10_000 })
})

test('rejects our own domains', async ({ page }) => {
  const company = page.getByTestId('company-acme')
  await page.goto('/')
  await company.getByLabel('Domain', { exact: true }).fill('admin.statuspage.com')
  await company.getByRole('button', { name: 'Add domain' }).click()
  await expect(page.getByRole('alert')).toHaveText(
    "Host can't be one of our own domains",
  )
})

test('requests that skip the proxy cannot claim a domain', async ({
  request,
}) => {
  const spoofed = await request.get('/', {
    headers: { 'X-Served-For': 'acme.test' },
  })
  expect(spoofed.status()).toBe(403)

  const wrongToken = await request.get('/', {
    headers: {
      'X-Served-For': 'acme.test',
      'X-SaaS-Domains-Auth-Token': 'guess',
    },
  })
  expect(wrongToken.status()).toBe(403)
})

test('webhooks need the right token', async ({ request }) => {
  const res = await request.post('/webhooks/saas_domains?token=x', {
    data: { event: 'domain_dns_proxy_record_valid', domain: { uuid: 'x' } },
  })
  expect(res.status()).toBe(401)
})

test('unknown domains get a 404', async ({ page }) => {
  const res = await page.goto(customerUrl('unknown.test'))
  expect(res?.status()).toBe(404)
})

test('Rails blocks hosts that are neither ours nor a customer domain', async ({
  request,
}) => {
  const blocked = await request.get('/', { headers: { Host: 'evil.example' } })
  expect(blocked.status()).toBe(403)

  // Load balancers call the health check by IP address.
  const health = await request.get('/up', { headers: { Host: '10.0.0.5' } })
  expect(health.status()).toBe(200)
})
