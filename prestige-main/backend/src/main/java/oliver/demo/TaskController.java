package oliver.demo;

import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

import java.util.List;

@RestController
@RequestMapping("/api/tasks") // All web requests to "/api/tasks" land here
@CrossOrigin(origins = "*")   // Prevents web security blocks when testing locally
public class TaskController {

    @Autowired
    private TaskRepository taskRepository;

    // 1. GET Request: Fetches all tasks from MySQL
    @GetMapping
    public List<Task> getAllTasks() {
        return taskRepository.findAll();
    }

    // 2. POST Request: Saves a new task into MySQL
    @PostMapping
    public Task createTask(@RequestBody Task task) {
        return taskRepository.save(task);
    }

    // 3. PUT Request: Updates an existing task details in MySQL
    @PutMapping("/{id}")
    public ResponseEntity<Task> updateTask(@PathVariable Long id, @RequestBody Task taskDetails) {
        
        // Find the existing task in the database by its ID
        Task existingTask = taskRepository.findById(id)
                .orElseThrow(() -> new RuntimeException("Task not found with id: " + id));

        // Change the old description to the new description sent from the frontend
        existingTask.setDescription(taskDetails.getDescription());

        // Save the changes back to MySQL (JPA updates the row instead of creating a new one because the ID matches)
        Task updatedTask = taskRepository.save(existingTask);

        // Return the updated task data to the frontend
        return ResponseEntity.ok(updatedTask);
    }

    // 4. DELETE Request: Removes a specific task from MySQL using its ID
    @DeleteMapping("/{id}")
    public ResponseEntity<String> deleteTask(@PathVariable Long id) {
        
        // Optional but recommended: Check if the task exists before trying to delete it
        if (!taskRepository.existsById(id)) {
            throw new RuntimeException("Task not found with id: " + id);
        }

        // Delete the row from the MySQL database
        taskRepository.deleteById(id);

        // Return a success message back to the frontend
        return ResponseEntity.ok("Task with ID " + id + " was successfully deleted.");
    }
}