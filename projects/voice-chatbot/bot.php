<?php

header('Content-Type: application/json; charset=utf-8');

require __DIR__ . '/../config.php';

// السماح فقط بطلبات POST
if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
    http_response_code(405);
    echo json_encode(['error' => 'الطريقة غير مسموحة']);
    exit;
}

$input = json_decode(file_get_contents('php://input'), true);
$prompt = trim($input['prompt'] ?? '');

if ($prompt === '') {
    http_response_code(400);
    echo json_encode(['error' => 'الرجاء إدخال رسالة']);
    exit;
}

if (!defined('OPENROUTER_API_KEY')) {
    http_response_code(500);
    echo json_encode(['error' => 'لم يتم العثور على مفتاح OpenRouter']);
    exit;
}

$url = "https://openrouter.ai/api/v1/chat/completions";

$models = [
    "google/gemma-3-4b-it:free",
    "openai/gpt-oss-20b:free",
    "inclusionai/ling-3.0-flash:free",
    "cohere/north-mini:free"
];

$reply = null;

foreach ($models as $model) {

    $data = [
        "model" => $model,
        "messages" => [
            [
                "role" => "user",
                "content" => $prompt
            ]
        ]
    ];

    $ch = curl_init("https://openrouter.ai/api/v1/chat/completions");

    curl_setopt_array($ch, [
        CURLOPT_RETURNTRANSFER => true,
        CURLOPT_POST => true,
        CURLOPT_HTTPHEADER => [
            "Authorization: Bearer " . OPENROUTER_API_KEY,
            "Content-Type: application/json"
        ],
        CURLOPT_POSTFIELDS => json_encode($data),
        CURLOPT_TIMEOUT => 30
    ]);

    $response = curl_exec($ch);

    if (curl_errno($ch)) {
        curl_close($ch);
        continue;
    }

    $http = curl_getinfo($ch, CURLINFO_HTTP_CODE);

    curl_close($ch);

    if ($http != 200) {
        continue;
    }

    $result = json_decode($response, true);

    if (isset($result['choices'][0]['message']['content'])) {
        $reply = $result['choices'][0]['message']['content'];
        break;
    }
}

if ($reply === null) {
    echo json_encode([
        "error" => "جميع النماذج المجانية غير متاحة حالياً."
    ], JSON_UNESCAPED_UNICODE);
    exit;
}

echo json_encode([
    "reply" => $reply
], JSON_UNESCAPED_UNICODE);