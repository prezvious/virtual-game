"use client";

import type { AnchorHTMLAttributes, ReactNode } from "react";

type FullDocumentLinkProps = Omit<AnchorHTMLAttributes<HTMLAnchorElement>, "href"> & {
  href: string;
  children: ReactNode;
};

export default function FullDocumentLink({ href, children, ...props }: FullDocumentLinkProps) {
  return (
    <a href={href} {...props}>
      {children}
    </a>
  );
}
