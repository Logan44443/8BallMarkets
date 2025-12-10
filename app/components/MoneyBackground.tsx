'use client'

export default function MoneyBackground() {
  // Create a large repeating grid that extends beyond viewport
  // This ensures seamless looping as it moves
  const tileSize = 100 // pixels per emoji tile
  const gridCols = 20 // Large enough to cover viewport + movement
  const gridRows = 20
  const totalEmojis = gridCols * gridRows

  return (
    <div 
      className="fixed inset-0 pointer-events-none overflow-hidden z-[1]"
    >
      {/* Animated Money Grid - large enough for seamless coverage */}
      <div className="absolute animate-slide-money" style={{ 
        top: '-20%',
        left: '-20%',
        width: '140%',
        height: '140%'
      }}>
        <div 
          className="grid opacity-12" 
          style={{ 
            gridTemplateColumns: `repeat(${gridCols}, ${tileSize}px)`,
            gridTemplateRows: `repeat(${gridRows}, ${tileSize}px)`,
            width: `${gridCols * tileSize}px`,
            height: `${gridRows * tileSize}px`
          }}
        >
          {Array.from({ length: totalEmojis }).map((_, i) => (
            <div key={i} className="text-4xl text-center select-none flex items-center justify-center">
              💰
            </div>
          ))}
        </div>
      </div>
    </div>
  )
}

