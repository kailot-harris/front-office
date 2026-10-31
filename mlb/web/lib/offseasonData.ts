import fs from 'fs';
import path from 'path';
import { OffseasonMonitorDataset } from './offseasonTypes';

export function getOffseasonMonitorData(): OffseasonMonitorDataset | null {
  const filePath = path.join(process.cwd(), 'public', 'data', 'offseason_monitor.json');
  if (!fs.existsSync(filePath)) return null;
  const fileContent = fs.readFileSync(filePath, 'utf-8');
  return JSON.parse(fileContent) as OffseasonMonitorDataset;
}
