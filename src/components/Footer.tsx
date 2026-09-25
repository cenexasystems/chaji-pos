import React from 'react'

export interface FooterProps {
  className?: string
}

export default function Footer({ className = '' }: FooterProps) {
  const currentYear = new Date().getFullYear()

  return (
    <footer
      role="contentinfo"
      className={`shrink-0 w-full border-t border-gray-100/90 bg-white/95 backdrop-blur-sm py-2 sm:py-2.5 pb-[max(0.5rem,env(safe-area-inset-bottom))] px-4 text-center text-[12px] font-semibold text-[#7A8A78] tracking-wide select-none print:hidden z-20 transition-colors ${className}`}
    >
      Powered by Cenexa Systems &copy; {currentYear}
    </footer>
  )
}
