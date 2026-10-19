'use client';

import { CalibrationBin } from '@/lib/types';

interface CalibrationCurveProps {
  bins: CalibrationBin[];
}

export default function CalibrationCurve({ bins }: CalibrationCurveProps) {
  // SVG Canvas dimensions
  const width = 500;
  const height = 350;
  const padding = 45;

  const innerWidth = width - padding * 2;
  const innerHeight = height - padding * 2;

  // Coordinate transforms (0.0 to 1.0)
  const getX = (val: number) => padding + val * innerWidth;
  const getY = (val: number) => height - padding - val * innerHeight;

  // Calculate points
  const points = bins.map((bin) => ({
    x: getX(bin.predicted_mid),
    y: getY(bin.actual_win_rate),
    pred: bin.predicted_mid,
    actual: bin.actual_win_rate,
    count: bin.count,
    binName: bin.bin,
  }));

  const linePath = points.reduce((acc, pt, idx) => {
    return `${acc} ${idx === 0 ? 'M' : 'L'} ${pt.x} ${pt.y}`;
  }, '');

  return (
    <div className="bg-slate-900/90 border border-slate-800 rounded-xl p-5 shadow-xl flex flex-col">
      <div className="flex items-center justify-between pb-4 border-b border-slate-800 mb-4">
        <div>
          <h2 className="text-base font-semibold text-white flex items-center gap-2">
            10-Bin Reliability Calibration Curve
            <span className="text-xs font-mono font-normal text-emerald-400 bg-emerald-950/60 border border-emerald-800/60 px-2 py-0.5 rounded-full">
              Probability vs. Realized Win Rate
            </span>
          </h2>
          <p className="text-xs text-slate-400">
            A perfectly calibrated model tracks the diagonal dashed line (45° line of identity).
          </p>
        </div>
        <div className="flex items-center gap-3 text-xs font-mono">
          <span className="flex items-center gap-1.5 text-slate-400">
            <span className="w-3 h-0.5 border-t border-dashed border-slate-500"></span>
            Ideal (45°)
          </span>
          <span className="flex items-center gap-1.5 text-emerald-400">
            <span className="w-3 h-0.5 bg-emerald-400"></span>
            Model Actual
          </span>
        </div>
      </div>

      <div className="relative w-full aspect-[5/3.5] max-h-[380px] select-none">
        <svg
          viewBox={`0 0 ${width} ${height}`}
          className="w-full h-full overflow-visible font-mono text-[10px]"
        >
          {/* Grid lines */}
          {[0, 0.2, 0.4, 0.6, 0.8, 1.0].map((tick) => (
            <g key={tick}>
              {/* Horizontal grid */}
              <line
                x1={padding}
                y1={getY(tick)}
                x2={width - padding}
                y2={getY(tick)}
                stroke="#334155"
                strokeDasharray="2,2"
                strokeWidth="0.8"
              />
              <text
                x={padding - 8}
                y={getY(tick) + 3}
                fill="#94a3b8"
                textAnchor="end"
              >
                {(tick * 100).toFixed(0)}%
              </text>

              {/* Vertical grid */}
              <line
                x1={getX(tick)}
                y1={padding}
                x2={getX(tick)}
                y2={height - padding}
                stroke="#334155"
                strokeDasharray="2,2"
                strokeWidth="0.8"
              />
              <text
                x={getX(tick)}
                y={height - padding + 15}
                fill="#94a3b8"
                textAnchor="middle"
              >
                {(tick * 100).toFixed(0)}%
              </text>
            </g>
          ))}

          {/* Ideal line (Diagonal) */}
          <line
            x1={getX(0)}
            y1={getY(0)}
            x2={getX(1)}
            y2={getY(1)}
            stroke="#64748b"
            strokeDasharray="4,4"
            strokeWidth="1.5"
          />

          {/* Model Curve Area / Line */}
          <path
            d={linePath}
            fill="none"
            stroke="#10b981"
            strokeWidth="2.5"
            strokeLinecap="round"
          />

          {/* Data Points */}
          {points.map((pt, i) => (
            <g key={i} className="group cursor-pointer">
              <circle
                cx={pt.x}
                cy={pt.y}
                r="4.5"
                fill="#022c22"
                stroke="#34d399"
                strokeWidth="2"
                className="transition-all hover:scale-150"
              />
              {/* Tooltip on hover */}
              <title>
                {`Bin: ${pt.binName} | Pred: ${(pt.pred * 100).toFixed(0)}% | Actual: ${(pt.actual * 100).toFixed(1)}% (${pt.count} games)`}
              </title>
            </g>
          ))}

          {/* Axis Labels */}
          <text
            x={width / 2}
            y={height - 8}
            fill="#cbd5e1"
            textAnchor="middle"
            className="font-sans text-[11px] font-semibold"
          >
            Predicted Win Probability
          </text>
          <text
            x={-height / 2}
            y={12}
            fill="#cbd5e1"
            textAnchor="middle"
            transform="rotate(-90)"
            className="font-sans text-[11px] font-semibold"
          >
            Actual Realized Win Rate
          </text>
        </svg>
      </div>

      <div className="pt-3 border-t border-slate-800 text-xs text-slate-400 flex items-center justify-between">
        <span>Evaluated over 10 deciles of predicted win probabilities</span>
        <span className="text-emerald-400 font-mono font-semibold">
          High Reliability Deciles 40%–70%
        </span>
      </div>
    </div>
  );
}
