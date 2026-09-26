import { Camera, CameraResultType } from '@capacitor/camera';

const API = 'http://localhost:54321/functions/v1';

export async function scanReceipt() {
  const photo = await Camera.getPhoto({ resultType: CameraResultType.Uri });
  return fetch(`${API}/scan`, { method: 'POST', body: photo.webPath });
}
