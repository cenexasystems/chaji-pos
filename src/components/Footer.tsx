import React from 'react'

export interface FooterProps {
  className?: string
}

export default function Footer({ className = '' }: FooterProps) {
  const currentYear = new Date().getFullYear()

  return (
    <footer
      role="contentinfo"
      className={`fixed bottom-0 left-0 right-0 w-full z-50 m-0 bg-white border-t border-gray-200 shadow-[0_-2px_10px_rgba(0,0,0,0.06)] py-2 sm:py-2.5 px-4 text-center text-[12px] font-semibold text-[#7A8A78] tracking-wide select-none print:hidden ${className}`}
      style={{
        position: 'fixed',
        bottom: 0,
        left: 0,
        right: 0,
        width: '100%',
        paddingBottom: 'max(0.5rem, env(safe-area-inset-bottom, 0px))',
      }}
    >
      Powered by Cenexa Systems &copy; {currentYear}
    </footer>
  )
}
