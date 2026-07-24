<?php

$servername = "sql306.infinityfree.com";
$username = "if0_42471177";
$password = "XXTrZJoFNS";
$dbname = "if0_42471177_db_ab";

$conn = new mysqli($servername, $username, $password, $dbname);

if ($conn->connect_error) {
    die("Connection Failed: " . $conn->connect_error);
}

if (isset($_POST['submit'])) {

    $name = $conn->real_escape_string($_POST['name']);
    $age  = (int)$_POST['age'];

    $sql = "INSERT INTO user(name, age, status)
            VALUES('$name','$age',0)";

    $conn->query($sql);

    header("Location: index.php");
    exit();
}

if (isset($_GET['toggle'])) {

    $id = (int)$_GET['toggle'];

    $conn->query("UPDATE user
                  SET status = IF(status=0,1,0)
                  WHERE id=$id");

    header("Location: index.php");
    exit();
}

$result = $conn->query("SELECT * FROM user ORDER BY id DESC");

?>

<!DOCTYPE html>
<html lang="en">
<head>

<meta charset="UTF-8">

<title>Student Status</title>

<link rel="stylesheet" href="style.css">

</head>

<body>

<div class="container">

<h2>Student Status System</h2>

<form method="POST">

<input type="text"
name="name"
placeholder="Enter Name"
required>

<input type="number"
name="age"
placeholder="Enter Age"
required>

<button type="submit"
name="submit">
Submit
</button>

</form>

<table>

<tr>

<th>ID</th>
<th>Name</th>
<th>Age</th>
<th>Status</th>
<th>Action</th>

</tr>

<?php while($row = $result->fetch_assoc()) { ?>

<tr>

<td><?= $row['id']; ?></td>

<td><?= $row['name']; ?></td>

<td><?= $row['age']; ?></td>

<td>

<?php
if($row['status']==0){
echo "0";
}else{
echo "1";
}
?>

</td>

<td>

<a href="?toggle=<?= $row['id']; ?>">
Toggle
</a>

</td>

</tr>

<?php } ?>

</table>

</div>

</body>
</html>