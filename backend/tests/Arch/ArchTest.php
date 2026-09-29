<?php

declare(strict_types=1);

// Базовые архитектурные правила. На этапе 3 сюда добавятся правила границ модулей.

arch('no debugging functions are left in code')
    ->expect(['dd', 'dump', 'ddd', 'ray', 'var_dump', 'print_r'])
    ->not->toBeUsed();

arch('app code uses strict types')
    ->expect('App')
    ->toUseStrictTypes();

arch()->preset()->security();
