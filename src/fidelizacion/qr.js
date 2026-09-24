import { toDataURL } from 'qrcode';

export function createCommerceQrImage(url) {
  return toDataURL(url, {
    errorCorrectionLevel: 'M',
    margin: 1,
    width: 220,
    color: {
      dark: '#102d4a',
      light: '#ffffff',
    },
  });
}
