# ZERO FRAME — план фотореализма

## Статус на 1 сентября 2026

- [x] Все прежние карты удалены вместе с `LevelBuilder`; единственный уровень — статический `scenes/levels/dev_test_grid.tscn` (greybox-грид для тестов, дневное HDRI-небо).
- [x] `WeaponTuningCamera` каждого оружия является фактической current-камерой оружейного `SubViewport`.
- [x] Единый HDR panorama sky, AgX, фиксированная экспозиция, мягкий bloom и нейтральный contrast.
- [x] Performance/High/Ultra переключаются в главном меню; недоступные SSR/SSIL/probes не включаются в Compatibility.
- [x] Poly Haven `grass_medium_01` использует low-poly tuft + MultiMesh, без коллизии и без player-interaction physics.
- [ ] Перезапустить CLI smoke-test на новой карте (Player на полу, AK camera current, parser/runtime errors нет).
- [ ] Художественные карты: сделать заново с нуля, когда тестовый грид перестанет быть достаточным.

## 1. Стабильная база

- Зафиксировать два пресета: 60 FPS для iGPU и High для дискретной GPU.
- Проверять frame time, draw calls, VRAM и shader compilation на каждой карте.
- Убрать runtime-генерацию: карты, Player, свет и камеры должны быть видны в редакторе.

## 2. Физически правильная сцена

- Единица масштаба — 1 метр; проверить двери, ступени, оружие и высоту камеры.
- Отделить render mesh от упрощённой collision mesh; не использовать мелкие детали скана для физики.
- Добавить LOD и visibility range для травы, мусора и мелкого реквизита.

## 3. PBR-материалы

- Одинаковая texel density; 2K для большинства поверхностей, 4K только для hero-assets.
- Проверить каналы ARM, OpenGL normal, roughness и отсутствие металличности у бетона/грунта.
- Разбить повторы декалями грязи, протечек, трещин и краёв, а не чрезмерным post-process.

## 4. Свет и отражения

- PhysicalSky + DirectionalLight3D должны иметь одно направление солнца; экспозиция не должна дробиться.
- AgX, мягкий bloom только от ярких источников; не давить тени contrast-фильтром.
- Low: sky ambient + SSAO. High: SSIL + SSR + reflection probes. SDFGI включать только после замера GPU frame time.
- Статические reflection probes для помещений; SSR не должен быть единственным источником отражений.

## 5. Камера и viewmodel

- WorldCamera рисует мир; WeaponCamera в отдельном SubViewport всегда рисует руки/оружие поверх мира.
- Ракурс берётся из `WeaponTuningCamera` в сцене каждого оружия; runtime не перезаписывает его позицию.
- Bodycam sway от реальной velocity, низкая частота шага, быстрый mouse response; шейдер bodycam остаётся слабым.

## 6. Финальный QA

- Эталонные скриншоты: улица, тёмный интерьер, блик на металле, трава вблизи и вдали, выстрел и декаль.
- Проход каждой карты: спавн на полу, нет телепортов, нет провалов, Esc возвращает в меню.
- Приёмка: нет parser/runtime errors; нет первого shader stutter после кэша; пресет 60 FPS укладывается в 16.7 ms.
