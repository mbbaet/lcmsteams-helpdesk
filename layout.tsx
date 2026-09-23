import "./globals.css";

export const metadata = {
  title: "Laguna College ICT Services",
  description: "MS Teams Support Portal",
};

export default function RootLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  return (
    <html lang="en">
      <body>{children}</body>
    </html>
  );
}
