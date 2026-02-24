# Domain Connection (Starter)

## 1) Deploy this folder
- Use Vercel and import `/Users/hectorruiz/Documents/New project/about-me-site` as a static project.
- Build command: none
- Output directory: `.`

## 2) Add your custom domain in Vercel
- In project settings, open `Domains`.
- Add your root domain (example: `yourdomain.com`) and `www` subdomain.

## 3) DNS records at your registrar
- `A` record for root (`@`) -> `76.76.21.21`
- `CNAME` for `www` -> `cname.vercel-dns.com`

## 4) Confirm HTTPS
- Wait for certificate provisioning in Vercel.
- Set one primary domain (either root or `www`) and redirect the other.

## 5) Final profile image path
- Put your image at: `assets/profile-nottokyo.jpg`
- The page is already configured to use it automatically.
