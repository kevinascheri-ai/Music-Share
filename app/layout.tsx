import type { Metadata } from 'next'
import './globals.css'

export const metadata: Metadata = {
  title: 'Suno Jam',
  description: 'Listen to Suno songs in sync with friends',
}

export default function RootLayout({
  children,
}: {
  children: React.ReactNode
}) {
  return (
    <html lang="en">
      <body className="antialiased min-h-screen">{children}</body>
    </html>
  )
}
