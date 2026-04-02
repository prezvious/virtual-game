import Link from "next/link";
import FullDocumentLink from "@/components/ui/FullDocumentLink";

export default function NotFound() {
  return (
    <main className="feedbackPage">
      <div className="feedbackCard">
        <p className="feedbackEyebrow">404</p>
        <h1 className="feedbackTitle">Page Not Found</h1>
        <p className="feedbackText">
          The page you&apos;re looking for doesn&apos;t exist or has been moved. Let&apos;s get you back on track.
        </p>
        <div className="feedbackActions">
          <Link href="/home" className="feedbackPrimary">
            Return Home
          </Link>
          <Link href="/account-center" className="feedbackSecondary">
            Account Center
          </Link>
          <FullDocumentLink href="/fish" className="feedbackSecondary">
            Open Virtual Fisher
          </FullDocumentLink>
        </div>
      </div>
    </main>
  );
}
