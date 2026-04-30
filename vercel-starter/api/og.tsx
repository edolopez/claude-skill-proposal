// /api/og — dynamic Open Graph image for proposal social previews.
//
// When a proposal URL is pasted in Slack, email, or LinkedIn, the unfurl
// pulls this image. The proposal HTML references it via:
//   <meta property="og:image" content="/api/og?title=...&client=...&company=...&color=..." />
//
// Query params:
//   title   — project codename (required)
//   client  — client company name (required)
//   company — your (seller) company name
//   color   — brand hex without # (e.g., "0B5FFF")
//   date    — proposal date (YYYY-MM-DD)
//
// Renders a 1200x630 image, restrained typographic style, brand color as accent.

import { ImageResponse } from '@vercel/og';

export const config = { runtime: 'edge' };

export default function handler(req: Request) {
  const url = new URL(req.url);
  const title = (url.searchParams.get('title') || 'Proposal').slice(0, 80);
  const client = (url.searchParams.get('client') || '').slice(0, 60);
  const company = (url.searchParams.get('company') || '').slice(0, 60);
  const colorHex = (url.searchParams.get('color') || '0F172A').replace(/[^0-9A-Fa-f]/g, '').slice(0, 6) || '0F172A';
  const brand = `#${colorHex.padEnd(6, '0')}`;
  const date = (url.searchParams.get('date') || '').slice(0, 10);

  return new ImageResponse(
    (
      <div
        style={{
          height: '100%',
          width: '100%',
          display: 'flex',
          flexDirection: 'column',
          justifyContent: 'space-between',
          padding: '72px 88px',
          background: '#fafafa',
          fontFamily: 'system-ui, -apple-system, sans-serif',
        }}
      >
        <div style={{ display: 'flex', flexDirection: 'column' }}>
          <div
            style={{
              fontSize: 18,
              letterSpacing: 6,
              textTransform: 'uppercase',
              color: '#64748b',
              fontWeight: 500,
            }}
          >
            {date ? `${date} · Proposal` : 'Proposal'}
          </div>
          <div
            style={{
              fontSize: 96,
              fontWeight: 500,
              letterSpacing: -2.5,
              color: '#0f172a',
              lineHeight: 1.05,
              marginTop: 24,
              maxWidth: 1024,
            }}
          >
            {title}
          </div>
        </div>

        <div
          style={{
            display: 'flex',
            justifyContent: 'space-between',
            alignItems: 'flex-end',
            paddingTop: 24,
            borderTop: '1px solid #e2e8f0',
          }}
        >
          <div style={{ display: 'flex', flexDirection: 'column' }}>
            {client ? (
              <>
                <div style={{ fontSize: 16, color: '#64748b', textTransform: 'uppercase', letterSpacing: 3 }}>
                  Prepared for
                </div>
                <div style={{ fontSize: 36, fontWeight: 600, color: '#0f172a', marginTop: 6 }}>{client}</div>
              </>
            ) : null}
          </div>
          <div style={{ display: 'flex', flexDirection: 'column', alignItems: 'flex-end' }}>
            {company ? (
              <>
                <div style={{ fontSize: 16, color: '#64748b', textTransform: 'uppercase', letterSpacing: 3 }}>
                  By
                </div>
                <div style={{ fontSize: 36, fontWeight: 600, color: brand, marginTop: 6 }}>{company}</div>
              </>
            ) : null}
          </div>
        </div>

        <div
          style={{
            position: 'absolute',
            top: 0,
            left: 0,
            width: '100%',
            height: 8,
            background: brand,
          }}
        />
      </div>
    ),
    {
      width: 1200,
      height: 630,
    }
  );
}
